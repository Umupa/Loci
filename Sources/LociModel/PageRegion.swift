/// A page of a PDF, or one rectangle on it.
///
/// The rectangle is in PDF page space: points, origin at the bottom left, to a hundredth of a point.
public struct PageRegion: Hashable, Sendable {
  /// Counted from 1.
  public let page: Int
  public let rect: Rect?

  public init(page: Int, rect: Rect? = nil) throws {
    guard page >= 1 else { throw ModelError("pages are counted from 1") }
    self.page = page
    self.rect = rect
  }

  init?(page text: String, taking fragment: inout Fragment) {
    guard let page = Int(digits: text) else { return nil }
    var rect: Rect?
    if let rectText = fragment.take("rect") {
      guard let parsed = Rect(fragmentValue: rectText) else { return nil }
      rect = parsed
    }
    guard let region = try? PageRegion(page: page, rect: rect) else { return nil }
    self = region
  }

  var fragment: String {
    Fragment.join([("page", String(page)), ("rect", rect?.fragmentValue)])
  }

  /// A rectangle with positive width and height.
  public struct Rect: Hashable, Sendable {
    private let hundredths: [Int]

    public init(x: Double, y: Double, width: Double, height: Double) throws {
      let values = [x, y, width, height]
      guard values.allSatisfy({ $0.isFinite && abs($0) < 1e12 }) else { throw ModelError("rectangle is not finite") }
      try self.init(hundredths: values.map { Int(($0 * 100).rounded()) })
    }

    private init(hundredths: [Int]) throws {
      guard hundredths[2] > 0, hundredths[3] > 0 else { throw ModelError("rectangle has no area") }
      self.hundredths = hundredths
    }

    public var x: Double { Double(hundredths[0]) / 100 }
    public var y: Double { Double(hundredths[1]) / 100 }
    public var width: Double { Double(hundredths[2]) / 100 }
    public var height: Double { Double(hundredths[3]) / 100 }

    init?(fragmentValue: String) {
      let parts = fragmentValue.split(separator: ",", omittingEmptySubsequences: false)
      let values = parts.compactMap { FixedPoint.units(String($0), decimals: 2) }
      guard parts.count == 4, values.count == 4, let rect = try? Rect(hundredths: values) else { return nil }
      self = rect
    }

    var fragmentValue: String {
      hundredths.map { FixedPoint.text($0, decimals: 2) }.joined(separator: ",")
    }
  }
}
