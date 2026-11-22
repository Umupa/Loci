import AppKit

/// A cover shrunk to a few pixels and drawn large again, so only its colors are left, a little darker; a
/// square cover can then sit whole in the middle of a wider frame with no letters showing around it.
enum CoverWash {
  private static let few = 6
  private static let side = 64
  static let byteBudget = side * side * 4

  static func of(_ image: NSImage) -> NSImage? {
    guard let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let tiny = bitmap(side: few), let wash = bitmap(side: side),
      let context = NSGraphicsContext(bitmapImageRep: tiny)
    else { return nil }
    context.cgContext.interpolationQuality = .high
    context.cgContext.draw(picture, in: CGRect(x: 0, y: 0, width: few, height: few))
    context.flushGraphics()
    let colors = (0..<few).map { y in (0..<few).map { x in tiny.colorAt(x: x, y: y) ?? .black } }
    let step = CGFloat(few - 1) / CGFloat(side - 1)
    for y in 0..<side {
      for x in 0..<side {
        wash.setColor(blend(colors, x: CGFloat(x) * step, y: CGFloat(y) * step), atX: x, y: y)
      }
    }
    return wash.cgImage.map { NSImage(cgImage: $0, size: NSSize(width: side, height: side)) }
  }

  private static func bitmap(side: Int) -> NSBitmapImageRep? {
    NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
  }

  /// The color between the four nearest of `colors` at a point measured in them, a little darkened.
  private static func blend(_ colors: [[NSColor]], x: CGFloat, y: CGFloat) -> NSColor {
    let left = min(Int(x), few - 2)
    let top = min(Int(y), few - 2)
    let across = x - CGFloat(left)
    let down = y - CGFloat(top)
    func mix(_ a: NSColor, _ b: NSColor, _ share: CGFloat) -> NSColor { a.blended(withFraction: share, of: b) ?? a }
    let upper = mix(colors[top][left], colors[top][left + 1], across)
    let lower = mix(colors[top + 1][left], colors[top + 1][left + 1], across)
    return mix(mix(upper, lower, down), .black, darkening)
  }

  private static let darkening: CGFloat = 0.12
}
