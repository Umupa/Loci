import SwiftUI

/// How a course's book is bound, worked out from its title alone: the same title always gets the same cloth and
/// the same drawing, on any Mac and after any restart.
struct BookDesign: Equatable {
  let motif: BookMotif
  let cloth: Int

  init(title: String) {
    let hash = Self.mixed(Self.fnv1a(title))
    let families = BookMotif.Family.allCases
    motif = BookMotif(
      family: families[Int(hash % UInt64(families.count))], count: Int((hash >> 12) % 4),
      dashed: (hash >> 20) & 1 == 1, turn: Int((hash >> 24) % 4))
    cloth = Int((hash >> 32) % UInt64(Palette.Cloth.all.count))
  }

  var clothColor: Color { Palette.Cloth.all[cloth] }

  /// Spreads every bit of `hash` over all the others (SplitMix64's finish), so neighbouring titles land on
  /// different cloths and drawings.
  static func mixed(_ hash: UInt64) -> UInt64 {
    var value = hash &+ 0x9E37_79B9_7F4A_7C15
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }

  /// FNV-1a over the title's UTF-8, which unlike `hashValue` is the same in every run.
  static func fnv1a(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in text.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01B3
    }
    return hash
  }
}

/// A single-colour line drawing on a cover: one of a few families, each varied by a count, whether its guide is
/// dashed, and a quarter turn.
struct BookMotif: Equatable {
  enum Family: CaseIterable {
    /// Machines in a ring, one leading.
    case ring
    /// A grid of cells, one picked.
    case grid
    /// Boxes inside boxes.
    case nested
    /// Layers growing wider downward.
    case layers
    /// A line that climbs and drops.
    case sawtooth
    /// Waves spreading from a point.
    case ripples
  }

  let family: Family
  /// 0 to 3, read by each family as its own count.
  let count: Int
  let dashed: Bool
  let turn: Int
}

/// Draws a motif in the cover's cream ink.
struct MotifDrawing: View {
  let motif: BookMotif
  var ink = Palette.clothInk.opacity(0.58)

  var body: some View {
    Canvas { context, size in
      let unit = min(size.width, size.height) / 100
      context.translateBy(x: (size.width - unit * 100) / 2, y: (size.height - unit * 100) / 2)
      context.scaleBy(x: unit, y: unit)
      draw(in: &context, line: 1.3 / max(unit, 0.3))
    }
    .accessibilityHidden(true)
  }

  private func draw(in context: inout GraphicsContext, line: CGFloat) {
    let stroke = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
    let dash = StrokeStyle(lineWidth: line, lineCap: .round, dash: [2, 4])
    let shading = GraphicsContext.Shading.color(ink)
    func path(_ build: (inout Path) -> Void) -> Path {
      var path = Path()
      build(&path)
      return path
    }
    switch motif.family {
    case .ring:
      let nodes = 4 + motif.count
      let points = (0..<nodes).map { index -> CGPoint in
        let angle = -Double.pi / 2 + Double(index) / Double(nodes) * 2 * .pi
        return CGPoint(x: 50 + cos(angle) * 34, y: 52 + sin(angle) * 34)
      }
      for (index, point) in points.enumerated() {
        context.stroke(
          Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)), with: shading, style: stroke)
        guard index > 0 else { continue }
        let lead = points[0]
        let dx = point.x - lead.x
        let dy = point.y - lead.y
        let length = max(hypot(dx, dy), 1)
        context.stroke(
          path {
            $0.move(to: CGPoint(x: lead.x + dx / length * 7, y: lead.y + dy / length * 7))
            $0.addLine(to: CGPoint(x: point.x - dx / length * 7, y: point.y - dy / length * 7))
          }, with: shading, style: stroke)
      }
      context.fill(
        Path(ellipseIn: CGRect(x: points[0].x - 2.5, y: points[0].y - 2.5, width: 5, height: 5)), with: shading)
      if motif.dashed {
        context.stroke(Path(ellipseIn: CGRect(x: 20, y: 22, width: 60, height: 60)), with: shading, style: dash)
      }
    case .grid:
      let side = motif.count < 2 ? 3 : 4
      let cell = 72 / CGFloat(side) - 4
      let step = 72 / CGFloat(side)
      for row in 0..<side {
        for column in 0..<side {
          let rect = CGRect(x: 14 + CGFloat(column) * step, y: 14 + CGFloat(row) * step, width: cell, height: cell)
          context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: shading, style: stroke)
        }
      }
      let picked = CGFloat(side / 2) * step + 14 + cell / 2
      context.fill(Path(ellipseIn: CGRect(x: picked - 4, y: picked - 4, width: 8, height: 8)), with: shading)
      context.stroke(
        path {
          $0.move(to: CGPoint(x: 18, y: 82))
          $0.addLine(to: CGPoint(x: 82, y: 18))
        }, with: shading, style: motif.dashed ? dash : stroke)
    case .nested:
      let rings = 3 + min(motif.count, 1)
      for ring in 0..<rings {
        let inset = 10 + CGFloat(ring) * (36 / CGFloat(rings))
        let rect = CGRect(x: inset, y: inset, width: 100 - inset * 2, height: 100 - inset * 2)
        let shape =
          motif.turn.isMultiple(of: 2)
          ? Path(roundedRect: rect, cornerRadius: 14 - CGFloat(ring) * 3) : Path(ellipseIn: rect)
        context.stroke(shape, with: shading, style: ring == rings - 1 && motif.dashed ? dash : stroke)
      }
      context.fill(Path(ellipseIn: CGRect(x: 46, y: 46, width: 8, height: 8)), with: shading)
    case .layers:
      let levels = 4 + min(motif.count, 1)
      let height: CGFloat = 10
      let gap = (80 - CGFloat(levels) * height) / CGFloat(levels - 1)
      for level in 0..<levels {
        let width = 24 + CGFloat(level) * (60 / CGFloat(levels - 1))
        let y = 10 + CGFloat(level) * (height + gap)
        context.stroke(
          Path(roundedRect: CGRect(x: 50 - width / 2, y: y, width: width, height: height), cornerRadius: 2),
          with: shading, style: stroke)
        if level < levels - 1 {
          context.stroke(
            path {
              $0.move(to: CGPoint(x: 50, y: y + height))
              $0.addLine(to: CGPoint(x: 50, y: y + height + gap))
            }, with: shading, style: StrokeStyle(lineWidth: line, dash: [2, 2]))
        }
      }
    case .sawtooth:
      let teeth = 3 + motif.count
      let step = 84 / CGFloat(teeth)
      context.stroke(
        path { line in
          line.move(to: CGPoint(x: 8, y: 80))
          for tooth in 0..<teeth {
            let x = 8 + CGFloat(tooth) * step
            let top = 36 - CGFloat(tooth) * (22 / CGFloat(teeth))
            line.addLine(to: CGPoint(x: x + step * 0.5, y: top))
            line.addLine(to: CGPoint(x: x + step * 0.5, y: top + 24))
            line.addLine(to: CGPoint(x: x + step, y: top - 6))
          }
        }, with: shading, style: stroke)
      context.stroke(
        path {
          $0.move(to: CGPoint(x: 8, y: 88))
          $0.addLine(to: CGPoint(x: 92, y: 88))
        }, with: shading, style: StrokeStyle(lineWidth: line, dash: [2, 3]))
    case .ripples:
      let waves = 3 + motif.count / 2
      let origin = CGPoint(x: 22, y: 78)
      for wave in 0..<waves {
        let radius = 18 + CGFloat(wave) * (52 / CGFloat(waves))
        context.stroke(
          path {
            $0.addArc(
              center: origin, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
          }, with: shading, style: wave == waves - 1 && motif.dashed ? dash : stroke)
      }
      context.fill(Path(ellipseIn: CGRect(x: origin.x - 4, y: origin.y - 4, width: 8, height: 8)), with: shading)
      context.stroke(
        path {
          $0.move(to: CGPoint(x: 86, y: 18))
          $0.addLine(to: CGPoint(x: 86, y: 30))
          $0.move(to: CGPoint(x: 80, y: 24))
          $0.addLine(to: CGPoint(x: 92, y: 24))
        }, with: shading, style: stroke)
    }
  }
}
