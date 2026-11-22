import Foundation
import LociModel
import Testing

@testable import LociStore

struct BundledPiFilesTests {
  @Test func aFailedReplacementLeavesThePreviouslyActiveVersionRunnable() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let support = Support(root: root)
    let old = try support.scratchFolder()
    try Data("#!/bin/sh\n".utf8).write(to: old.appending(path: "pi"))
    let first = EntityID()
    try support.activatePi(old, version: "1.5.0", generation: first)
    let before = try #require(support.activePi())
    #expect(before.version == "1.5.0")
    #expect(support.isExecutable(before.executable))

    let broken = try support.scratchFolder()
    #expect(throws: (any Error).self) { try support.activatePi(broken, version: "1.6.0", generation: EntityID()) }
    #expect(support.activePi()?.executable == before.executable)

    let new = try support.scratchFolder()
    try Data("#!/bin/sh\n".utf8).write(to: new.appending(path: "pi"))
    try support.activatePi(new, version: "1.6.0", generation: EntityID())
    #expect(support.activePi()?.version == "1.6.0")
    #expect(support.isExecutable(before.executable))
  }
}
