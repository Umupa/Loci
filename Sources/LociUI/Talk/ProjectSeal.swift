import LociModel
import SwiftUI

/// A project's monochrome SF Symbol seal. A project kept out of memory carries a small lock, and one with news
/// carries an amber dot, each cleanly punched out of the symbol; the row that starts a new project, without a
/// symbol, shows a dashed outline.
struct ProjectSeal: View {
  let symbol: String
  var size: CGFloat = Size.seal
  var selected = false
  var locked = false
  var unseen = false
  var ghost = false

  var body: some View {
    let dotSize = max(size * 0.29, 5.5)
    let lockSize = size * 0.44
    let badgeOffset = size * 0.1
    face
      .compositingGroup()
      .mask {
        SealMask(
          unseen: unseen, locked: locked, dotDiameter: dotSize + 3.4, lockDiameter: lockSize + 2.2,
          dotCenterOffset: badgeOffset, dotVisualDiameter: dotSize, lockVisualDiameter: lockSize
        )
        .fill(style: FillStyle(eoFill: true))
      }
      .overlay(alignment: .topTrailing) {
        if unseen {
          Circle()
            .fill(Palette.accent)
            .frame(width: dotSize, height: dotSize)
            .offset(x: badgeOffset, y: -badgeOffset)
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if locked {
          Image(systemName: "lock.fill")
            .font(.system(size: size * 0.27, weight: .bold))
            .foregroundStyle(Palette.inkMuted)
            .frame(width: lockSize, height: lockSize)
            .offset(x: badgeOffset, y: badgeOffset)
        }
      }
  }

  @ViewBuilder private var face: some View {
    if ghost, symbol.isEmpty {
      RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
        .strokeBorder(Palette.inkFaint, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
        .frame(width: size, height: size)
    } else {
      Image(systemName: symbol.isEmpty ? ProjectIcon.fallback : symbol)
        .symbolRenderingMode(.monochrome)
        .font(.system(size: size * 0.66, weight: selected ? .semibold : .medium))
        .animation(nil, value: selected)
        .foregroundStyle(ghost ? Palette.inkMuted : (selected ? Palette.ink : Palette.inkMuted))
        .frame(width: size, height: size)
    }
  }
}

extension Project {
  /// Its name, or what a project is called before it has one.
  var title: Text {
    name.map { Text(verbatim: $0) } ?? Text(.loci("projects.new"))
  }
}

extension ProjectSeal {
  /// A long name cut to what fits a line, as the field's prompt says it.
  static func shortened(_ name: String) -> String {
    name.count > 10 ? String(name.prefix(9)) + "…" : name
  }
}

/// Punches true transparent holes out of a seal for its corner badges using the even-odd fill rule.
private struct SealMask: Shape {
  let unseen: Bool
  let locked: Bool
  let dotDiameter: CGFloat
  let lockDiameter: CGFloat
  let dotCenterOffset: CGFloat
  let dotVisualDiameter: CGFloat
  let lockVisualDiameter: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path(rect.insetBy(dx: -rect.width, dy: -rect.height))
    if unseen {
      let center = CGPoint(
        x: rect.maxX - dotVisualDiameter / 2 + dotCenterOffset,
        y: rect.minY + dotVisualDiameter / 2 - dotCenterOffset)
      path.addEllipse(
        in: CGRect(
          x: center.x - dotDiameter / 2, y: center.y - dotDiameter / 2, width: dotDiameter, height: dotDiameter))
    }
    if locked {
      let center = CGPoint(
        x: rect.maxX - lockVisualDiameter / 2 + dotCenterOffset,
        y: rect.maxY - lockVisualDiameter / 2 + dotCenterOffset)
      path.addEllipse(
        in: CGRect(
          x: center.x - lockDiameter / 2, y: center.y - lockDiameter / 2, width: lockDiameter, height: lockDiameter))
    }
    return path
  }
}
