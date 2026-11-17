import Foundation
import Testing

@testable import LociAgents

struct AgentProgramsTests {
  @Test func onlyInstalledProgramsThatLociCanDriveHaveADriver() throws {
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-programs-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["grok", "fx"] {
      let program = folder.appending(path: name)
      try Data("#!/bin/sh\n".utf8).write(to: program)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
    }
    let programs = AgentPrograms(search: AgentSearch(directories: [folder]))

    #expect(programs.driver(for: .grok)?.provider == .grok)
    #expect(programs.driver(for: .pi) == nil)
    #expect(programs.driver(for: .fx) == nil)
  }
}
