import Foundation
import LociModel

extension Store {
  static let soulFile = "SOUL.md"
  /// The name agent programs look for instructions under. It links to `SOUL.md`, so there is one text.
  static let agentInstructionsFile = "AGENTS.md"

  /// The folder a mentor's agent works in.
  public func workingFolder(of mentor: EntityID) throws -> URL {
    try mentorFolder(mentor)
  }

  /// Gives the mentor its soul unless it has one: `SOUL.md` is written once and then belongs to the person
  /// and the mentor; `AGENTS.md` points to it so every agent program reads it.
  public func installSoul(_ text: String, for mentor: EntityID) throws {
    let folder = try mentorFolder(mentor)
    let soul = folder.appending(path: Self.soulFile)
    if !FileManager.default.fileExists(atPath: soul.path(percentEncoded: false)) {
      try write(Data(text.utf8), to: soul)
    }
    let instructions = folder.appending(path: Self.agentInstructionsFile)
    let linked = (try? FileManager.default.destinationOfSymbolicLink(atPath: instructions.path(percentEncoded: false)))
    if linked == nil, !FileManager.default.fileExists(atPath: instructions.path(percentEncoded: false)) {
      try FileManager.default.createSymbolicLink(
        atPath: instructions.path(percentEncoded: false), withDestinationPath: Self.soulFile)
    }
  }
}
