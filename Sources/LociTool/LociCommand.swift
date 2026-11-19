import Foundation
import LociModel

/// `loci`: what Loci runs, inside a session the app started, to search and add to the library.
@main
enum LociCommand {
  static func main() async {
    let outcome = await run(
      Array(CommandLine.arguments.dropFirst()), environment: ProcessInfo.processInfo.environment,
      folder: URL.currentDirectory())
    let output = outcome.status == 0 ? FileHandle.standardOutput : FileHandle.standardError
    output.write(Data((outcome.text + "\n").utf8))
    exit(outcome.status)
  }

  static func run(_ arguments: [String], environment: [String: String], folder: URL) async -> Tool.Outcome {
    let parsed: (request: Request, json: Bool)
    do throws(UsageError) {
      parsed = try Request.parse(arguments)
    } catch {
      return Tool.Outcome(text: error.message, status: 2)
    }
    if parsed.request == .help { return .worked(ToolGuide.text) }
    guard let socket = environment[LocalCall.socketVariable], !socket.isEmpty else {
      return .failed(Failure.outsideLoci.message)
    }
    let line = SocketLine(
      socket: URL(filePath: socket),
      conversation: environment[LocalCall.sessionVariable].flatMap(ConversationRef.init(tag:)))
    let tool = Tool(line: line, folder: folder) { try String(contentsOf: $0, encoding: .utf8) }
    return await tool.run(parsed.request, json: parsed.json)
  }
}
