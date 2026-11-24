import Foundation
import LociAgents
import LociModel
import Synchronization

/// An agent that behaves as a test says, recording what it was asked.
final class FakeAgent: AgentDriver, Sendable {
  enum Behavior: Sendable {
    /// Replies in a few pieces.
    case reply(String)
    /// Asks before running `echo`; runs it only when allowed.
    case askToRun
    /// Works until interrupted.
    case hang
    /// Starts reading a file, then works until interrupted.
    case readAndHang(String)
    /// Writes these files, relative to Loci's folder, then replies.
    case write([String: String], reply: String)
    /// Says how full its context window is, then replies.
    case report(ContextUsage, reply: String)
    /// Compacts its context, then replies.
    case compact(reply: String)
    /// The model's side fails partway, with these words.
    case fail(String)
    /// Waits until the test lets it go, then replies.
    case replyWhenLetGo(String, after: @Sendable () async -> Void)
  }

  let provider: Provider
  private let behave: @Sendable (String) -> Behavior
  private let state = Mutex<(prompts: [String], opened: [SessionConfiguration], sessions: Int)>(([], [], 0))

  init(provider: Provider = .pi, _ behave: @escaping @Sendable (String) -> Behavior = { _ in .reply("Hello there.") }) {
    self.provider = provider
    self.behave = behave
  }

  var prompts: [String] { state.withLock { $0.prompts } }
  var opened: [SessionConfiguration] { state.withLock { $0.opened } }

  func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession {
    if let resume = configuration.resume, !resume.value.hasPrefix("fake-") { throw .sessionNotFound }
    let number = state.withLock { state in
      state.opened.append(configuration)
      state.sessions += 1
      return state.sessions
    }
    let handle = configuration.resume ?? SessionHandle(provider: provider, value: "fake-\(number)")
    return FakeSession(handle: handle, folder: configuration.workingDirectory, agent: self)
  }

  fileprivate func behavior(for prompt: String) -> Behavior {
    state.withLock { $0.prompts.append(prompt) }
    return behave(prompt)
  }
}

private actor FakeSession: AgentSession {
  nonisolated let handle: SessionHandle
  private let folder: URL
  private let agent: FakeAgent
  private var answers: [String: CheckedContinuation<PermissionAnswer, Never>] = [:]
  private var interrupted: CheckedContinuation<Void, Never>?
  private var busy = false
  private var wasInterrupted = false

  init(handle: SessionHandle, folder: URL, agent: FakeAgent) {
    self.handle = handle
    self.folder = folder
    self.agent = agent
  }

  func send(_ text: String) async throws(AgentError) -> Turn {
    guard !busy else { throw .turnInProgress }
    busy = true
    wasInterrupted = false
    let (events, out) = AsyncStream.makeStream(of: AgentEvent.self)
    let behavior = agent.behavior(for: text)
    Task {
      let end = await self.play(behavior, out)
      out.yield(.ended(end))
      out.finish()
      self.idle()
    }
    return Turn(events: events)
  }

  func interrupt() async {
    if busy { wasInterrupted = true }
    interrupted?.resume()
    interrupted = nil
    for (_, waiting) in answers { waiting.resume(returning: .dismissed) }
    answers = [:]
  }

  func answer(_ request: PermissionRequest.ID, with answer: PermissionAnswer) async {
    answers.removeValue(forKey: request.value)?.resume(returning: answer)
  }

  func close() async { await interrupt() }

  private func idle() { busy = false }

  private func play(_ behavior: FakeAgent.Behavior, _ out: AsyncStream<AgentEvent>.Continuation) async -> TurnEnd {
    switch behavior {
    case .reply(let text):
      for piece in text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
        out.yield(.text((piece.offset == 0 ? "" : " ") + piece.element))
      }
      return .completed
    case .askToRun:
      let call = ToolCall(
        id: .init("call-1"), name: "bash", kind: .execute, input: .object(["command": .string("echo hi")]))
      out.yield(.toolCall(call))
      out.yield(
        .permission(
          PermissionRequest(
            id: .init("ask-1"), title: "bash", toolCall: call.id,
            options: [
              .init(id: "allow", role: .allow), .init(id: "deny", role: .deny),
            ])))
      let answer = await withCheckedContinuation { answers["ask-1"] = $0 }
      if answer == .chosen("allow") {
        out.yield(.toolCallChanged(call.id, .finished(output: "hi\n", failed: false)))
        out.yield(.text("It printed hi."))
      } else {
        out.yield(.toolCallChanged(call.id, .finished(output: "The user did not allow this.", failed: true)))
        out.yield(.text("I did not run it."))
      }
      return .completed
    case .hang:
      out.yield(.text("Working"))
      if !wasInterrupted { await withCheckedContinuation { interrupted = $0 } }
      return .interrupted
    case .readAndHang(let path):
      out.yield(
        .toolCall(ToolCall(id: .init("read-1"), name: "read", kind: .read, input: .object(["path": .string(path)]))))
      if !wasInterrupted { await withCheckedContinuation { interrupted = $0 } }
      return .interrupted
    case .write(let files, let reply):
      for (path, text) in files.sorted(by: { $0.key < $1.key }) {
        let url = folder.appending(path: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
      }
      out.yield(.text(reply))
      return .completed
    case .report(let usage, let reply):
      out.yield(.context(usage))
      out.yield(.text(reply))
      return .completed
    case .compact(let reply):
      out.yield(.notice(.compacting))
      out.yield(.text(reply))
      return .completed
    case .fail(let reason):
      return .failed(.provider(reason))
    case .replyWhenLetGo(let text, let after):
      await after()
      out.yield(.text(text))
      return .completed
    }
  }
}
