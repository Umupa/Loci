import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociAgents

/// Every agent program can run `loci`, and knows which conversation it is in.
struct AgentToolTests {
  private final class CapturingLauncher: ProgramLauncher {
    let invocations = Mutex<[Invocation]>([])

    func launch(_ invocation: Invocation) throws(AgentError) -> RunningProgram {
      invocations.withLock { $0.append(invocation) }
      throw .cannotLaunch("Captured")
    }
  }

  @Test(arguments: [Provider.codex, .claudeCode, .pi, .grok])
  func aSessionsProgramFindsLociFirstAndIsToldItsConversation(provider: Provider) async throws {
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-programs-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let name = try #require(AgentCLI.all.first { $0.provider == provider }?.names.first)
    try Data("#!/bin/sh\n".utf8).write(to: folder.appending(path: name))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: name).path)
    let launcher = CapturingLauncher()
    let tool = AgentTool(
      folder: URL(filePath: "/Applications/Loci.app/Contents/Helpers"), socket: URL(filePath: "/s/loci.sock"))
    let programs = AgentPrograms(
      search: AgentSearch(directories: [folder]), tool: tool, environment: ["HOME": "/Users/me"], launcher: launcher)
    let driver = try #require(programs.driver(for: provider))

    _ = try? await driver.open(
      SessionConfiguration(workingDirectory: URL(filePath: "/agent"), environment: [LocalCall.sessionVariable: "main"]))

    let environment = try #require(launcher.invocations.withLock { $0.first?.environment })
    #expect(environment["PATH"] == "/Applications/Loci.app/Contents/Helpers:\(folder.path(percentEncoded: false))")
    #expect(environment[LocalCall.socketVariable] == "/s/loci.sock")
    #expect(environment[LocalCall.commandVariable] == "/Applications/Loci.app/Contents/Helpers/loci")
    #expect(environment[LocalCall.sessionVariable] == "main")
    #expect(environment["HOME"] == "/Users/me")
  }
}
