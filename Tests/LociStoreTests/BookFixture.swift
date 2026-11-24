import Foundation

/// ZIP archives and EPUBs made in the test, so no downloaded book is needed.
enum BookFixture {
  static func archive(_ files: [(name: String, data: Data, deflated: Bool)]) -> Data {
    var body = Data()
    var directory = Data()
    for file in files {
      let packed =
        file.deflated ? (try? (file.data as NSData).compressed(using: .zlib) as Data) ?? file.data : file.data
      let name = Data(file.name.utf8)
      let method: UInt16 = file.deflated ? 8 : 0
      let offset = UInt32(body.count)
      body += le32(0x0403_4b50) + le16(20) + le16(0) + le16(method) + le16(0) + le16(0) + le32(0)
      body += le32(UInt32(packed.count)) + le32(UInt32(file.data.count)) + le16(UInt16(name.count)) + le16(0)
      body += name + packed
      directory += le32(0x0201_4b50) + le16(20) + le16(20) + le16(0) + le16(method) + le16(0) + le16(0) + le32(0)
      directory += le32(UInt32(packed.count)) + le32(UInt32(file.data.count)) + le16(UInt16(name.count))
      directory += le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + name
    }
    let end =
      le32(0x0605_4b50) + le16(0) + le16(0) + le16(UInt16(files.count)) + le16(UInt16(files.count))
      + le32(UInt32(directory.count)) + le32(UInt32(body.count)) + le16(0)
    return body + directory + end
  }

  static func chapter(_ title: String, _ body: String, language: String = "zh") -> String {
    """
    <?xml version="1.0" encoding="utf-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="\(language)"><head><title>\(title)</title></head>
    <body><h1>\(title)</h1>\(body)</body></html>
    """
  }

  static let nav = """
    <?xml version="1.0" encoding="utf-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
    <nav epub:type="landmarks"><ol><li><a href="c1.xhtml">Start</a></li></ol></nav>
    <nav epub:type="toc"><ol>
      <li><a href="c1.xhtml">自序</a></li>
      <li><span>小說</span><ol>
        <li><a href="c2.xhtml#s1">狂人<em>日記</em></a></li>
        <li><a href="sub/../c3.xhtml">孔乙己</a></li>
      </ol></li>
    </ol></nav></body></html>
    """

  static let ncx = """
    <?xml version="1.0" encoding="utf-8"?>
    <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><navMap>
      <navPoint id="a"><navLabel><text>One</text></navLabel><content src="c1.xhtml"/>
        <navPoint id="b"><navLabel><text>Two</text></navLabel><content src="c2.xhtml#x"/></navPoint>
      </navPoint>
    </navMap></ncx>
    """

  /// An EPUB with three chapters under `OPS/`. `meta` goes into the metadata, `manifest` into the manifest, and
  /// `extra` adds files.
  static func epub(
    title: String? = "吶喊", creators: [String] = ["魯迅"], meta: String = "", manifest: String = "",
    navigation: Bool = true, ncx: Bool = false, extra: [(String, Data)] = [], container: Bool = true
  ) -> Data {
    let titleLine = title.map { "<dc:title>\($0)</dc:title>" } ?? ""
    let creatorLines = creators.map { "<dc:creator>\($0)</dc:creator>" }.joined()
    let opf = """
      <?xml version="1.0" encoding="utf-8"?>
      <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">x</dc:identifier>
      \(titleLine)\(creatorLines)<dc:language>zh-Hant</dc:language>\(meta)</metadata>
      <manifest>
      <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
      <item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>
      <item id="c3" href="c3.xhtml" media-type="application/xhtml+xml"/>
      <item id="style" href="style.css" media-type="text/css"/>
      \(navigation ? #"<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>"# : "")
      \(ncx ? #"<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>"# : "")
      \(manifest)
      </manifest>
      <spine\(ncx ? #" toc="ncx""# : "")><itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3"/></spine>
      </package>
      """
    var files: [(String, Data, Bool)] = [("mimetype", Data("application/epub+zip".utf8), false)]
    if container {
      files.append(
        (
          "META-INF/container.xml",
          Data(
            """
            <?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles><rootfile full-path="OPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>
            """.utf8), true
        ))
    }
    files += [
      ("OPS/content.opf", Data(opf.utf8), true),
      ("OPS/c1.xhtml", Data(chapter("自序", "<p>我在年青時候也曾經做過許多夢。</p>").utf8), true),
      ("OPS/c2.xhtml", Data(chapter("狂人日記", #"<p id="s1">今天晚上，很好的月光。</p>"#).utf8), true),
      ("OPS/c3.xhtml", Data(chapter("孔乙己", "<p>魯鎮的酒店的格局。</p>").utf8), true),
      ("OPS/style.css", Data("p { color: red }".utf8), true),
    ]
    if navigation { files.append(("OPS/nav.xhtml", Data(nav.utf8), true)) }
    if ncx { files.append(("OPS/toc.ncx", Data(Self.ncx.utf8), true)) }
    files += extra.map { ($0.0, $0.1, true) }
    return archive(files.map { (name: $0.0, data: $0.1, deflated: $0.2) })
  }

  static func write(_ data: Data, named name: String) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "loci-book-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: name)
    try data.write(to: file)
    return file
  }

  private static func le16(_ value: UInt16) -> Data { Data([UInt8(value & 0xFF), UInt8(value >> 8)]) }
  private static func le32(_ value: UInt32) -> Data { le16(UInt16(value & 0xFFFF)) + le16(UInt16(value >> 16)) }
}
