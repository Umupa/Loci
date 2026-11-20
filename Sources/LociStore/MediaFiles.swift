import Foundation
import LociModel

/// The files a video or audio item gathers as its job runs, each written by one stage: `cover.*` and the
/// platform's chapters on resolving, `media.*` on downloading, `transcript.json` on recognizing,
/// `translations/<language>.json` and `outline.json` from the agent. Unfinished work waits in `.work/`.
extension Store {
  static let transcriptFile = "transcript.json"
  static let outlineFile = "outline.json"
  static let translationsFolder = "translations"
  static let workFolder = ".work"
  static let mediaName = "media"
  static let coverName = "cover"

  /// Makes the folder of an item whose content is still to come, with only its `item.json`.
  public func addPending(_ item: Item) throws {
    guard !folderExists(holding: item.id, in: libraryFolder, file: Self.itemFile) else {
      throw StoreError.alreadyExists(item.id)
    }
    let folder = libraryFolder.appending(path: FolderName.make(for: item.title, id: item.id))
    try write(Formats.document(item), to: folder.appending(path: Self.itemFile))
  }

  /// Rewrites `item.json`, and renames the folder after the new title when its name still follows the old
  /// one. A name someone chose by hand is kept.
  public func retitle(_ item: Item, from old: String) throws {
    let folder = try itemFolder(item.id)
    try write(Formats.document(item), to: folder.appending(path: Self.itemFile))
    guard folder.lastPathComponent == FolderName.make(for: old, id: item.id) else { return }
    let renamed = libraryFolder.appending(path: FolderName.make(for: item.title, id: item.id))
    guard renamed != folder, !FileManager.default.fileExists(atPath: renamed.path(percentEncoded: false)) else {
      return
    }
    try FileManager.default.moveItem(at: folder, to: renamed)
  }

  /// A folder inside the item's for unfinished work, such as downloads in progress.
  public func workFolder(of item: EntityID) throws -> URL {
    let folder = try itemFolder(item).appending(path: Self.workFolder, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  /// Removes the unfinished work once a stage no longer needs it.
  public func clearWork(of item: EntityID) throws {
    let folder = try itemFolder(item).appending(path: Self.workFolder, directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
    try FileManager.default.removeItem(at: folder)
  }

  public func saveWork(_ data: Data, named name: String, of item: EntityID) throws -> URL {
    let file = try workFolder(of: item).appending(path: name)
    try write(data, to: file)
    return file
  }

  /// Removes one file from the work folder, if it is there.
  public func removeWork(named name: String, of item: EntityID) throws {
    guard let file = try workFile(named: name, of: item) else { return }
    try FileManager.default.removeItem(at: file)
  }

  /// A file in the work folder; `nil` when it is not there.
  public func workFile(named name: String, of item: EntityID) throws -> URL? {
    try existing(workFolder(of: item).appending(path: name))
  }

  /// A text file in the work folder, such as subtitles yt-dlp saved there; `nil` when it is not there.
  public func workText(named name: String, of item: EntityID) throws -> String? {
    try existing(itemFolder(item).appending(path: Self.workFolder).appending(path: name)).map(readText)
  }

  /// The item's media, which may be a link to a file elsewhere; `nil` until it is downloaded or imported.
  public func mediaFile(of item: EntityID) throws -> URL? {
    named(Self.mediaName, in: try itemFolder(item))
  }

  /// How many bytes the item's media takes in its folder; `nil` without a file of its own there, as for one
  /// played online or linked to where it is.
  public func mediaBytes(of item: EntityID) throws -> Int64? {
    guard let file = try mediaFile(of: item),
      let values = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
      values.isSymbolicLink != true
    else { return nil }
    return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
  }

  /// Deletes the item's media file and any part of a download, leaving everything made from it.
  public func deleteMedia(of item: EntityID) throws {
    if let file = try mediaFile(of: item) { try FileManager.default.removeItem(at: file) }
    try clearWork(of: item)
  }

  /// The size of the disk the data folder is on, and how much of it is free.
  public func disk() -> (capacity: Int64?, available: Int64?) {
    let values = try? root.resourceValues(forKeys: [
      .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
    ])
    return (values?.volumeTotalCapacity.map(Int64.init), values?.volumeAvailableCapacityForImportantUsage)
  }

  /// Moves a finished download in as `media.<extension>`, replacing any earlier one.
  @discardableResult
  public func adoptMedia(_ file: URL, of item: EntityID) throws -> URL {
    let folder = try itemFolder(item)
    if let earlier = named(Self.mediaName, in: folder) { try FileManager.default.removeItem(at: earlier) }
    let target = folder.appending(path: "\(Self.mediaName).\(file.pathExtension.lowercased())")
    try FileManager.default.moveItem(at: file, to: target)
    return target
  }

  /// Brings a file on this Mac in as the item's media: a copy, or a link to where it is.
  @discardableResult
  public func importMedia(_ source: URL, as mode: ImportMode, of item: EntityID) throws -> URL {
    guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
      throw StoreError.notFound(source.path(percentEncoded: false))
    }
    let folder = try itemFolder(item)
    let target = folder.appending(path: "\(Self.mediaName).\(source.pathExtension.lowercased())")
    switch mode {
    case .copy: try FileManager.default.copyItem(at: source, to: target)
    case .link: try FileManager.default.createSymbolicLink(at: target, withDestinationURL: source)
    }
    return target
  }

  public func coverFile(of item: EntityID) throws -> URL? {
    named(Self.coverName, in: try itemFolder(item))
  }

  public func cover(of item: EntityID) throws -> Data? {
    try coverFile(of: item).map(read)
  }

  /// Saves the cover as `cover.<extension>`, replacing any earlier one.
  public func saveCover(_ data: Data, extension pathExtension: String, of item: EntityID) throws {
    let folder = try itemFolder(item)
    if let earlier = named(Self.coverName, in: folder) { try FileManager.default.removeItem(at: earlier) }
    try write(data, to: folder.appending(path: "\(Self.coverName).\(pathExtension.lowercased())"))
  }

  /// Copies a picture in as the cover, replacing any earlier one.
  public func saveCover(copying picture: URL, of item: EntityID) throws {
    try saveCover(try read(picture), extension: picture.pathExtension, of: item)
  }

  private func named(_ stem: String, in folder: URL) -> URL? {
    let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    return entries.filter { $0.deletingPathExtension().lastPathComponent == stem && !$0.pathExtension.isEmpty }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }.first
  }

  /// `nil` until the first sentence is written.
  public func transcript(of item: EntityID) throws -> Transcript? {
    try existing(itemFolder(item).appending(path: Self.transcriptFile)).map { try decodeJSON(Transcript.self, at: $0) }
  }

  public func save(_ transcript: Transcript, of item: EntityID) throws {
    try write(Formats.document(transcript), to: itemFolder(item).appending(path: Self.transcriptFile))
  }

  /// Every translation, by language; files that cannot be read are left out.
  public func translations(of item: EntityID) throws -> [Translation] {
    let folder = try itemFolder(item).appending(path: Self.translationsFolder, directoryHint: .isDirectory)
    return files(in: folder, withExtension: "json").compactMap { try? decodeJSON(Translation.self, at: $0) }
  }

  public func save(_ translation: Translation, of item: EntityID) throws {
    let folder = try itemFolder(item).appending(path: Self.translationsFolder, directoryHint: .isDirectory)
    try write(Formats.document(translation), to: folder.appending(path: "\(translation.language).json"))
  }

  public func outline(of item: EntityID) throws -> Outline? {
    try existing(itemFolder(item).appending(path: Self.outlineFile)).map { try decodeJSON(Outline.self, at: $0) }
  }

  public func save(_ outline: Outline, of item: EntityID) throws {
    try write(Formats.document(outline), to: itemFolder(item).appending(path: Self.outlineFile))
  }

  func existing(_ file: URL) -> URL? {
    FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) ? file : nil
  }
}
