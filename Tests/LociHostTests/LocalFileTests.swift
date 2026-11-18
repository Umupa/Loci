import Foundation
import LociModel
import Testing

@testable import LociHost

/// Paths on this Mac never cross the Host: files go in as uploads and come out as `LocalFile`s.
struct LocalFileTests {
  @Test func anUploadIsUsedByOneImportOnly() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      let file = world.place.root.appending(path: ".outside/talk.wav")
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Silence.wav(seconds: 1).write(to: file)
      let upload = try await host.upload(LocalFile(file))

      _ = try await host.run(ImportMediaFile(upload: upload, mode: .copy))

      await #expect(throws: HostError.notFound("upload \(upload.id)")) {
        try await host.run(ImportMediaFile(upload: upload, mode: .copy))
      }
    }
  }

  @Test func downloadedMediaIsReadInRanges() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      let file = world.place.root.appending(path: ".outside/talk.wav")
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      let sound = Silence.wav(seconds: 1)
      try sound.write(to: file)
      let item = try await host.run(
        ImportMediaFile(upload: try await host.upload(LocalFile(file)), mode: .copy))

      let info = try await host.run(ReadMediaFileInfo(item: item.id))
      let middle = try await host.run(ReadMediaBytes(item: item.id, offset: 10, length: 20))
      let end = try await host.run(ReadMediaBytes(item: item.id, offset: info.byteCount - 4, length: 100))
      let past = try await host.run(ReadMediaBytes(item: item.id, offset: info.byteCount + 1, length: 100))

      #expect(info == MediaFileInfo(byteCount: Int64(sound.count), fileExtension: "wav"))
      #expect(middle == sound.subdata(in: 10..<30))
      #expect(end == sound.suffix(4))
      #expect(past.isEmpty)
      #expect(await host.localFile(.media(item.id))?.url.lastPathComponent == "media.wav")
    }
  }

  @Test func locisFolderIsALocalFile() async throws {
    try await withHost { host, place, _ in
      let folder = await host.localFile(.agentFolder)

      #expect(folder?.url.standardizedFileURL == place.root.appending(path: "agent").standardizedFileURL)
    }
  }
}
