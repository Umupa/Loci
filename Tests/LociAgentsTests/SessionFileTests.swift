import Foundation
import LociAgents
import LociModel
import Testing

/// US-S1, US-S6: a CLI's session file, read down to tokens, context and where the context came from.
struct SessionFileTests {
  private static let claudeCode = [
    #"{"type":"user","message":{"role":"user","content":"Refresh the weather panel."}}"#,
    #"{"type":"assistant","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"cd /x; curl -s https://api.example.com/weather"}}],"usage":{"input_tokens":3,"cache_creation_input_tokens":2000,"cache_read_input_tokens":28000,"output_tokens":100}}}"#,
    #"{"type":"assistant","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"text","text":"…"}],"usage":{"input_tokens":3,"cache_creation_input_tokens":2000,"cache_read_input_tokens":28000,"output_tokens":120}}}"#,
    #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"sunny 18°C"}]}}"#,
    #"{"type":"assistant","message":{"id":"m2","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"\"$LOCI\" panel save weather <<'EOF'\n{}\nEOF"}}],"usage":{"input_tokens":2,"cache_creation_input_tokens":900,"cache_read_input_tokens":30003,"output_tokens":300}}}"#,
  ].joined(separator: "\n")

  @Test func aClaudeCodeReplyWrittenOverSeveralLinesIsOneCall() throws {
    let usage = try #require(SessionFile(claudeCode: Self.claudeCode).usage(instructions: 2000))
    #expect(usage.calls == 2)
    #expect(usage.tokens == TokenCounts(input: 5, cacheWrite: 2900, cacheRead: 58003, output: 420))
    #expect(usage.tokens.fresh == 3325)
    #expect(usage.context == ContextSpan(start: 30003, end: 30905, peak: 30905))
    #expect(usage.model == "claude-opus-5-5")
  }

  @Test func theFirstCallsContextIsTheCLIAgentsAndTheFirstMessage() throws {
    let usage = try #require(SessionFile(claudeCode: Self.claudeCode).usage(instructions: 2000))
    let parts = Dictionary(uniqueKeysWithValues: usage.makeup.map { ($0.source, $0.tokens) })
    let prompt = TokenEstimate.of("Refresh the weather panel.")
    #expect(parts[.instructions] == 2000)
    #expect(parts[.prefix] == prompt)
    #expect(parts[.runtime] == 30003 - 2000 - prompt)
    #expect(parts[.output] == 120)
    #expect(parts[.tool("curl")] == 902 - 120)
    #expect(usage.makeup.map(\.tokens).reduce(0, +) == usage.context.end)
    #expect(usage.makeup.first?.source == .runtime)
  }

  @Test func aSessionThatSavedAPanelWroteSomething() throws {
    #expect(SessionFile(claudeCode: Self.claudeCode).wrote)
    let reading = Self.claudeCode.replacingOccurrences(of: "panel save weather", with: "panel list")
    #expect(!SessionFile(claudeCode: reading).wrote)
  }

  @Test func codexCountsEachTokenCountOnceAndTakesTheCachedPartOutOfInput() throws {
    let text = [
      #"{"type":"turn_context","payload":{"model":"gpt-6.2-sol"}}"#,
      #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Look at CubeSandbox."}]}}"#,
      #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20000},"last_token_usage":{"input_tokens":20000,"cached_input_tokens":0,"output_tokens":50}}}}"#,
      #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20000},"last_token_usage":{"input_tokens":20000,"cached_input_tokens":0,"output_tokens":50}}}}"#,
      #"{"type":"response_item","payload":{"type":"custom_tool_call","call_id":"c1","name":"exec","input":"await tools.exec_command({cmd:\"gh pr list -R a/b\"})"}}"#,
      ##"{"type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"c1","output":[{"type":"input_text","text":"#1 fix"}]}}"##,
      #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":41000},"last_token_usage":{"input_tokens":21000,"cached_input_tokens":19900,"output_tokens":80}}}}"#,
    ].joined(separator: "\n")
    let usage = try #require(SessionFile(codex: text).usage(instructions: 0))
    #expect(usage.calls == 2)
    #expect(usage.tokens == TokenCounts(input: 21100, cacheWrite: 0, cacheRead: 19900, output: 130))
    #expect(usage.context == ContextSpan(start: 20000, end: 21000, peak: 21000))
    #expect(usage.makeup.contains(ContextPart(.tool("gh"), tokens: 950)))
    #expect(usage.model == "gpt-6.2-sol")
  }

  @Test func aFileWithNoCallsHasNoUsage() {
    #expect(SessionFile(claudeCode: #"{"type":"user","message":{"content":"hi"}}"#).usage(instructions: 0) == nil)
  }

  @Test(arguments: [
    ("cd /Users/x/agent; R=a/b\ngh pr list -R $R", "gh", false),
    ("T=$(( $(date +%s) - 7 ))\nfor q in a b; do curl -s \"https://x/$q\"; done", "curl", false),
    ("cd /x; \"$LOCI\" panel save radar <<'EOF'", "loci panel", true),
    ("loci read https://example.com", "loci read", false),
    ("loci schedule list", "loci schedule", false),
    ("ego-browser nodejs <<'EOF'", "ego-browser", false),
    ("python3 -c 'print(1)'", "python3", false),
    ("cd /x && echo hi", "shell", false),
  ])
  func aShellCommandIsNamedByWhatItRan(command: String, name: String, writes: Bool) {
    let label = ToolLabel(command: command)
    #expect(label.name == name)
    #expect(label.writes == writes)
  }

  @Test func claudeCodeFilesAreFoundByTheirSessionAndCodexFilesInTheDaysAroundIt() throws {
    let folders = SessionFolders.home(URL(filePath: "/Users/x"), environment: [:])
    let started = Timestamp(Date(timeIntervalSince1970: 1_795_600_000))
    let claude = try #require(
      folders.search(provider: .claudeCode, handle: "abc", startedAt: started, timeZone: .gmt))
    #expect(claude.folders == [URL(filePath: "/Users/x/.claude/projects")])
    #expect(claude.depth == 1)
    #expect(claude.name.matches("abc.jsonl"))
    let codex = try #require(folders.search(provider: .codex, handle: "t-1", startedAt: started, timeZone: .gmt))
    #expect(codex.folders.map { $0.path(percentEncoded: false) }.contains("/Users/x/.codex/sessions/2026/11/25"))
    #expect(codex.name.matches("rollout-2026-11-25T10-29-05-t-1.jsonl"))
    #expect(folders.search(provider: .pi, handle: "p", startedAt: started, timeZone: .gmt) == nil)
  }
}
