import CryptoKit
import Foundation

public struct TranslationCacheKey: Hashable, Sendable {
  public let digest: String

  public init(_ components: [String]) {
    var hash = SHA256()
    for component in components {
      var size = UInt64(component.utf8.count).bigEndian
      withUnsafeBytes(of: &size) { hash.update(bufferPointer: $0) }
      hash.update(data: Data(component.utf8))
    }
    digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

extension Store {
  private var translationCacheFolder: URL { root.appending(path: ".translation-cache", directoryHint: .isDirectory) }

  private func translationCacheFile(_ key: TranslationCacheKey) -> URL {
    translationCacheFolder.appending(path: key.digest + ".txt")
  }

  public func cachedTranslation(for key: TranslationCacheKey) -> String? {
    try? readText(translationCacheFile(key))
  }

  public func cacheTranslations(_ translations: [TranslationCacheKey: String]) throws {
    for (key, text) in translations {
      try write(Data(text.utf8), to: translationCacheFile(key))
    }
  }

  public func translationCacheBytes() -> Int64 {
    files(in: translationCacheFolder, withExtension: "txt").reduce(0) { bytes, file in
      bytes + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
  }

  public func clearTranslationCache() throws {
    do {
      try FileManager.default.removeItem(at: translationCacheFolder)
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
    }
  }
}
