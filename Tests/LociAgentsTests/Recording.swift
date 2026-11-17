import Foundation
import Synchronization

@testable import LociAgents

/// One step of a recorded session with Pi, in the order it happened.
enum Step: Equatable {
  /// Pi was started with these arguments.
  case launch([String])
  /// The driver wrote this record.
  case to(JSONValue)
  /// Pi wrote this record.
  case from(JSONValue)
  /// The driver closed Pi's input.
  case close
  /// Pi ended, having written this to standard error.
  case exit(Int32, String)

  init?(_ value: JSONValue) {
    if let arguments = value["launch"]?.array {
      self = .launch(arguments.compactMap(\.string))
    } else if let record = value["to"] {
      self = .to(record)
    } else if let record = value["from"] {
      self = .from(record)
    } else if value["close"] != nil {
      self = .close
    } else if let code = value["exit"]?.int {
      self = .exit(Int32(code), value["stderr"]?.string ?? "")
    } else {
      return nil
    }
  }

  var json: JSONValue {
    switch self {
    case .launch(let arguments): .object(["launch": .array(arguments.map(JSONValue.string))])
    case .to(let record): .object(["to": record])
    case .from(let record): .object(["from": record])
    case .close: .object(["close": .bool(true)])
    case .exit(let code, let said): .object(["exit": .number(Double(code)), "stderr": .string(said)])
    }
  }
}

enum Recording {
  static func load(_ name: String) throws -> [Step] {
    guard let file = Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures") else {
      throw CocoaError(.fileNoSuchFile)
    }
    return try String(contentsOf: file, encoding: .utf8).split(separator: "\n").compactMap {
      Step(try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)))
    }
  }

  static func line(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: (try? encoder.encode(value)) ?? Data(), as: UTF8.self)
  }

  static func records(in data: Data) -> [JSONValue] {
    var framer = LineFramer()
    return framer.receive(data).compactMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
  }

  /// Arguments with this machine's paths replaced by names, so a recording made here replays anywhere.
  static func portable(_ arguments: [String], folder: URL) -> [String] {
    arguments.map { argument in
      if argument == PiDriver.askBeforeTools?.path { return "$GATE" }
      return argument.replacing(folder.path, with: "$FOLDER")
    }
  }
}

/// Starts the real program and keeps both directions of the conversation, and when it ended, to be saved
/// as a fixture.
final class RecordingLauncher: ProgramLauncher {
  private struct Run {
    var steps: [Step]
    var said = Data()
    var drained: Task<Void, Never>?
  }

  private let folder: URL
  private let runs = Mutex<[Run]>([])

  init(folder: URL) {
    self.folder = folder
  }

  func launch(_ invocation: Invocation) throws(AgentError) -> RunningProgram {
    let real = try SystemLauncher().launch(invocation)
    let index = runs.withLock {
      $0.append(Run(steps: [.launch(Recording.portable(invocation.arguments, folder: folder))]))
      return $0.count - 1
    }
    let (output, forward) = AsyncStream.makeStream(of: Data.self)
    let (diagnostics, forwardDiagnostics) = AsyncStream.makeStream(of: Data.self)
    let drained = Task {
      async let errors: Void = {
        for await chunk in real.diagnostics {
          self.runs.withLock { $0[index].said.append(chunk) }
          forwardDiagnostics.yield(chunk)
        }
        forwardDiagnostics.finish()
      }()
      var framer = LineFramer()
      for await chunk in real.output {
        let records = framer.receive(chunk).compactMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        self.runs.withLock { $0[index].steps += records.map(Step.from) }
        forward.yield(chunk)
      }
      await errors
      let code = await real.exit()
      self.runs.withLock { $0[index].steps.append(.exit(code, String(decoding: $0[index].said, as: UTF8.self))) }
      forward.finish()
    }
    runs.withLock { $0[index].drained = drained }
    return RunningProgram(
      output: output, diagnostics: diagnostics,
      write: { data in
        self.runs.withLock { $0[index].steps += Recording.records(in: data).map(Step.to) }
        try real.write(data)
      },
      closeInput: {
        self.runs.withLock { $0[index].steps.append(.close) }
        real.closeInput()
      },
      terminate: real.terminate, exit: real.exit)
  }

  /// Writes the conversation, without this machine's details or Pi's system prompt, as `<name>.jsonl` in `directory`.
  func save(_ name: String, to directory: URL) async throws {
    for run in runs.withLock({ $0 }) { await run.drained?.value }
    let lines = runs.withLock { $0 }.flatMap(\.steps).map { Recording.line(Self.scrubbed($0.json)) }
    var text = lines.joined(separator: "\n")
      .replacing(folder.resolvingSymlinksInPath().path, with: "$FOLDER")
      .replacing(folder.path, with: "$FOLDER")
      .replacing(NSHomeDirectory(), with: "$HOME")
    for (name, stand) in runs.withLock({ $0 }).flatMap(\.steps).flatMap(Self.modelNames) {
      text = text.replacing(name, with: stand)
    }
    try Data((text + "\n").utf8).write(to: directory.appending(path: "\(name).jsonl"))
  }

  /// The names of the model and of whoever serves it, which say how this machine is set up.
  private static func modelNames(_ step: Step) -> [(String, String)] {
    guard case .from(let record) = step, record["command"]?.string == "get_state", let model = record["data"]?["model"]
    else { return [] }
    return [("id", "some-model"), ("name", "Some Model"), ("provider", "some-provider")].compactMap { key, stand in
      model[key]?.string.map { ($0, stand) }
    }
  }

  private static func scrubbed(_ value: JSONValue) -> JSONValue {
    switch value {
    case .object(let members):
      .object(
        members.reduce(into: [:]) { result, member in
          switch member.key {
          case "baseUrl": result[member.key] = .string("")
          case "sections": break
          default: result[member.key] = scrubbed(member.value)
          }
        })
    case .array(let values): .array(values.map(scrubbed))
    default: value
    }
  }
}
