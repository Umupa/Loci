import Foundation
import LociModel
import Testing

@testable import LociStore

struct SupportTests {
  static func withSupport(_ body: (Support) throws -> Void) throws {
    let support = Support(root: FileManager.default.temporaryDirectory.appending(path: "loci-support-\(UUID())"))
    defer { try? FileManager.default.removeItem(at: support.root) }
    try body(support)
  }

  @Test func anInstalledComponentCanBeRun() throws {
    try Self.withSupport { support in
      let unpacked = try support.scratchFolder()
      try Data("#!/bin/sh\n".utf8).write(to: unpacked.appending(path: "yt-dlp_macos"))

      try support.installComponent(.ytDlp, unpacked: unpacked, executable: "yt-dlp_macos")

      let installed = support.components.appending(path: "ytDlp/yt-dlp_macos")
      #expect(support.isExecutable(installed))
      #expect(!FileManager.default.fileExists(atPath: unpacked.path))
    }
  }

  @Test func updatingAComponentReplacesItsWholeFolder() throws {
    try Self.withSupport { support in
      let first = try support.scratchFolder()
      try Data("old".utf8).write(to: first.appending(path: "leftover"))
      try Data("1".utf8).write(to: first.appending(path: "qjs"))
      try support.installComponent(.quickJS, unpacked: first, executable: "qjs")
      let download = support.root.appending(path: "qjs-download")
      try Data("2".utf8).write(to: download)

      try support.installComponent(.quickJS, unpacked: try support.stage(download, as: "qjs"), executable: "qjs")

      let folder = support.components.appending(path: "quickJS")
      #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["qjs"])
      #expect(try Data(contentsOf: folder.appending(path: "qjs")) == Data("2".utf8))
    }
  }

  @Test func aSpeechModelCanBeInstalledAndDeleted() throws {
    try Self.withSupport { support in
      let download = support.root.appending(path: "download.bin")
      try FileManager.default.createDirectory(at: support.root, withIntermediateDirectories: true)
      try Data("ggml".utf8).write(to: download)

      try support.installModel(download, as: "ggml-base.bin")
      #expect(support.hasModel("ggml-base.bin"))

      try support.deleteModel("ggml-base.bin")
      #expect(!support.hasModel("ggml-base.bin"))
      try support.deleteModel("ggml-base.bin")
    }
  }

  @Test func browserCookiesAreWrittenForYtDlpAndKeptPrivate() throws {
    try Self.withSupport { support in
      try support.saveCookies([
        BrowserCookie(
          domain: ".bilibili.com", path: "/", name: "SESSDATA", value: "abc", secure: true,
          expires: Timestamp(millisecondsSince1970: 1_800_000_000_000)),
        BrowserCookie(domain: "www.youtube.com", path: "/", name: "PREF", value: "f1", secure: false, expires: nil),
      ])

      #expect(
        try String(contentsOf: support.cookies, encoding: .utf8) == """
          # Netscape HTTP Cookie File
          .bilibili.com\tTRUE\t/\tTRUE\t1800000000\tSESSDATA\tabc
          www.youtube.com\tFALSE\t/\tFALSE\t0\tPREF\tf1

          """)
      let permissions = try FileManager.default.attributesOfItem(atPath: support.cookies.path)[.posixPermissions]
      #expect(permissions as? Int == 0o600)
    }
  }
}
