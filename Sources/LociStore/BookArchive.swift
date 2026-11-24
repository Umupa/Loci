import Foundation

/// A ZIP archive read in place: its directory once, then any one file on demand. Only what EPUBs use is
/// understood: files stored as they are or deflated, in an archive under 4 GB.
struct BookArchive {
  private let data: Data
  private let entries: [String: Entry]

  struct Entry {
    let method: UInt16
    let encrypted: Bool
    let compressedSize: Int
    let size: Int
    let offset: Int
  }

  enum Failure: Error, Equatable {
    /// Not a ZIP archive, or one cut short.
    case notAnArchive
    case damaged(String)
    case missing(String)
  }

  init(_ file: URL) throws {
    try self.init(data: try Data(contentsOf: file, options: .alwaysMapped))
  }

  init(data: Data) throws {
    self.data = data
    let bytes = [UInt8](data.suffix(65_557))
    guard bytes.count >= 22,
      let end = stride(from: bytes.count - 22, through: 0, by: -1).first(where: { bytes.u32($0) == 0x0605_4b50 })
    else { throw Failure.notAnArchive }
    let count = Int(bytes.u16(end + 10))
    let directorySize = Int(bytes.u32(end + 12))
    let directoryOffset = Int(bytes.u32(end + 16))
    guard directoryOffset + directorySize <= data.count else { throw Failure.notAnArchive }
    let directory = [UInt8](
      data[(data.startIndex + directoryOffset)..<(data.startIndex + directoryOffset + directorySize)])
    var entries: [String: Entry] = [:]
    var at = 0
    for _ in 0..<count {
      guard at + 46 <= directory.count, directory.u32(at) == 0x0201_4b50 else {
        throw Failure.damaged("central directory")
      }
      let nameLength = Int(directory.u16(at + 28))
      let skipped = Int(directory.u16(at + 30)) + Int(directory.u16(at + 32))
      guard at + 46 + nameLength <= directory.count else { throw Failure.damaged("central directory") }
      let name = String(decoding: directory[(at + 46)..<(at + 46 + nameLength)], as: UTF8.self)
      entries[name] = Entry(
        method: directory.u16(at + 10), encrypted: directory.u16(at + 8) & 1 != 0,
        compressedSize: Int(directory.u32(at + 20)), size: Int(directory.u32(at + 24)),
        offset: Int(directory.u32(at + 42)))
      at += 46 + nameLength + skipped
    }
    self.entries = entries
  }

  var names: some Collection<String> { entries.keys }

  func contains(_ name: String) -> Bool { entries[name] != nil }

  /// The size of a file once it is unpacked.
  func size(of name: String) -> Int? { entries[name]?.size }

  func file(_ name: String) throws -> Data {
    guard let entry = entries[name] else { throw Failure.missing(name) }
    guard !entry.encrypted else { throw Failure.damaged("\(name) is encrypted") }
    let header = data.startIndex + entry.offset
    guard header + 30 <= data.endIndex, [UInt8](data[header..<(header + 30)]).u32(0) == 0x0403_4b50 else {
      throw Failure.damaged(name)
    }
    let fields = [UInt8](data[(header + 26)..<(header + 30)])
    let start = header + 30 + Int(fields.u16(0)) + Int(fields.u16(2))
    guard start + entry.compressedSize <= data.endIndex else { throw Failure.damaged(name) }
    let packed = data[start..<(start + entry.compressedSize)]
    switch entry.method {
    case 0:
      return Data(packed)
    case 8:
      guard entry.size > 0 else { return Data() }
      guard let unpacked = try? (Data(packed) as NSData).decompressed(using: .zlib) as Data,
        unpacked.count == entry.size
      else { throw Failure.damaged(name) }
      return unpacked
    default:
      throw Failure.damaged("\(name) is packed in an unknown way")
    }
  }
}

extension [UInt8] {
  fileprivate func u16(_ at: Int) -> UInt16 { UInt16(self[at]) | UInt16(self[at + 1]) << 8 }
  fileprivate func u32(_ at: Int) -> UInt32 { UInt32(u16(at)) | UInt32(u16(at + 2)) << 16 }
}
