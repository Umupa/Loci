import AppKit
import LociModel

/// A picture standing in the reading text: the address the item's text names it with, the character it
/// stands on, and where it is drawn in the text view.
struct ReaderPictureSpot: Equatable {
  let address: String
  let location: Int
  let frame: CGRect

  var range: NSRange { NSRange(location: location, length: 1) }
}

extension ReaderTextView {
  /// How far left of a highlighted picture its amber bar stands, in the margin.
  static let pictureBarOffset: CGFloat = 18

  /// Where the picture on the character at `location` is drawn, or `nil` when there is no picture there.
  func pictureFrame(at location: Int) -> CGRect? {
    guard let storage = textStorage, location < storage.length,
      storage.attribute(.readerPicture, at: location, effectiveRange: nil) != nil,
      let content = contentStorage, let layoutManager = textLayoutManager,
      let place = content.location(content.documentRange.location, offsetBy: location),
      let fragment = layoutManager.textLayoutFragment(for: place)
    else { return nil }
    let attachment = fragment.frameForTextAttachment(at: place)
    guard !attachment.isEmpty else { return nil }
    let origin = fragment.layoutFragmentFrame.origin
    return attachment.offsetBy(dx: origin.x + textContainerOrigin.x, dy: origin.y + textContainerOrigin.y)
  }

  /// The picture under a point in this view, if there is one.
  func pictureSpot(at point: CGPoint) -> ReaderPictureSpot? {
    guard let location = offset(at: point), let frame = pictureFrame(at: location), frame.contains(point),
      let address = textStorage?.attribute(.readerPicture, at: location, effectiveRange: nil) as? String
    else { return nil }
    return ReaderPictureSpot(address: address, location: location, frame: frame)
  }

  func hover(_ spot: ReaderPictureSpot?) {
    guard spot != hoveredPicture else { return }
    hoveredPicture = spot
    pictureHovered(spot)
  }

  /// The amber line under a band of words that has a thought.
  static func underline(_ band: CGRect) -> CGRect {
    CGRect(x: band.minX + 1, y: band.maxY - 1.5, width: band.width - 2, height: 1.5)
  }

  /// All a highlighted picture's marks cover: its frame, the glow around it and the bar in the margin.
  static func markedArea(of picture: CGRect) -> CGRect {
    picture.insetBy(dx: -6, dy: -6).union(
      CGRect(x: picture.minX - pictureBarOffset, y: picture.minY, width: 3, height: 1))
  }

  /// A soft amber glow and a firmer amber line around the picture, and an amber bar in the margin beside it.
  static func drawMarked(_ picture: CGRect) {
    Tones.accent.withAlphaComponent(0.15).setStroke()
    let glow = NSBezierPath(
      roundedRect: picture.insetBy(dx: -4, dy: -4), xRadius: Radius.group + 4, yRadius: Radius.group + 4)
    glow.lineWidth = 4
    glow.stroke()
    Tones.accent.withAlphaComponent(0.6).setStroke()
    let edge = NSBezierPath(
      roundedRect: picture.insetBy(dx: -1, dy: -1), xRadius: Radius.group + 1, yRadius: Radius.group + 1)
    edge.lineWidth = 2
    edge.stroke()
    Tones.accent.setFill()
    let bar = CGRect(x: picture.minX - pictureBarOffset, y: picture.minY + 6, width: 3, height: picture.height - 12)
    NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
  }

  /// Sweeps a band of amber light across a picture once, as it is highlighted.
  func sweep(_ picture: CGRect) {
    let view = PictureSweep(frame: picture)
    addSubview(view)
    view.run()
  }
}

/// A band of amber light that crosses a picture once and goes away.
private final class PictureSweep: NSView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = Radius.group
    layer?.masksToBounds = true
  }

  required init?(coder: NSCoder) { nil }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func run() {
    guard let layer else { return }
    let band = CAGradientLayer()
    let amber = Tones.accent.withAlphaComponent(0.32).cgColor
    let clear = Tones.accent.withAlphaComponent(0).cgColor
    band.colors = [clear, amber, clear]
    band.locations = [0.3, 0.5, 0.7]
    band.startPoint = CGPoint(x: 0, y: 0.4)
    band.endPoint = CGPoint(x: 1, y: 0.6)
    band.frame = bounds
    layer.addSublayer(band)
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in self?.removeFromSuperview() }
    let move = CABasicAnimation(keyPath: "position.x")
    move.fromValue = -bounds.width / 2
    move.toValue = bounds.width * 1.5
    move.duration = 1
    move.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
    move.fillMode = .forwards
    move.isRemovedOnCompletion = false
    band.add(move, forKey: "sweep")
    CATransaction.commit()
  }
}
