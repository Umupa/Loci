import LociModel
import SwiftUI

/// The title page on the desk while the goal is settled: the title, a subtitle, and five lines under a rule —
/// what it is for, what matters most, what is known already, how deep, how long. A line not yet known is a
/// pencil guide; words come up in ink as they arrive. Once the goal is settled the page is sealed.
struct TitlePage: View {
  let title: String
  let goal: CourseGoal
  let sealed: Bool
  /// A line caught part way through being inked, for a snapshot.
  var held: (line: Int, progress: Double)?
  /// The course has just been started, so even what is on the page already comes up in ink.
  var newlyStarted = false
  /// What was already written when the page opened, which is not inked again.
  @State private var found: Written?

  /// The words on the page, line by line.
  private struct Written: Equatable {
    var title = ""
    var subtitle: String?
    var lines: [String?] = Array(repeating: nil, count: 5)
  }

  var body: some View {
    let already = found ?? (newlyStarted ? Written() : written)
    VStack(alignment: .leading, spacing: 0) {
      Ornament().padding(.bottom, 34)
      InkedText(serif: title, Typography.titlePageTitle, fresh: title != already.title)
        .id(title)
        .lineLimit(2)
        .minimumScaleFactor(0.6)
        .frame(minHeight: 46, alignment: .topLeading)
      subtitle(fresh: goal.subtitle != already.subtitle)
        .padding(.top, Spacing.s)
      Rectangle().fill(Palette.leafInk.opacity(0.25)).frame(height: Size.hairline)
        .padding(.top, 22).padding(.bottom, 18)
      ForEach(Array(goal.lines.enumerated()), id: \.offset) { index, line in
        GoalLine(
          symbol: Self.symbols[index], text: line, guide: Self.guides[index],
          fresh: line != already.lines[index], held: held?.line == index ? held?.progress : nil
        )
        .anchorPreference(key: FlightEnds.self, value: .bounds) { [.line(index): $0] }
      }
      Spacer(minLength: 0)
    }
    .foregroundStyle(Palette.leafInk)
    .padding(.top, 46).padding(.horizontal, 36).padding(.bottom, 30)
    .frame(width: Size.titlePage.width, height: Size.titlePage.height, alignment: .topLeading)
    .background { Paper() }
    .overlay(alignment: .bottomTrailing) {
      if sealed {
        Seal().padding(.trailing, 24).padding(.bottom, 22)
          .transition(.modifier(active: SealDrop(progress: 0), identity: SealDrop(progress: 1)))
      }
    }
    .animation(Motion.stamp, value: sealed)
    .rotationEffect(.degrees(-1.2))
    .onAppear {
      if found == nil { found = newlyStarted ? Written() : written }
    }
  }

  private var written: Written {
    Written(title: title, subtitle: goal.subtitle, lines: goal.lines)
  }

  @ViewBuilder private func subtitle(fresh: Bool) -> some View {
    if let subtitle = goal.subtitle {
      InkedText(serif: subtitle, Typography.titlePageSubtitle, fresh: fresh)
        .id(subtitle)
        .foregroundStyle(Palette.leafInk.opacity(0.62))
        .lineSpacing(4)
        .frame(minHeight: 48, alignment: .topLeading)
    } else {
      VStack(alignment: .leading, spacing: 22) {
        PencilGuide().frame(width: 230)
        PencilGuide().frame(width: 146)
      }
      .padding(.top, 10)
      .frame(minHeight: 48, alignment: .topLeading)
    }
  }

  private static let symbols = ["scope", "bolt", "checkmark.circle", "arrow.down.to.line", "book.closed"]
  /// How long each line's guide is, so the empty page does not look ruled.
  private static let guides: [CGFloat] = [0.76, 0.68, 0.54, 0.62, 0.44]
}

/// One line under the rule: its mark, and its words or a pencil guide.
private struct GoalLine: View {
  let symbol: String
  let text: String?
  let guide: CGFloat
  let fresh: Bool
  let held: Double?

  var body: some View {
    HStack(alignment: .top, spacing: 11) {
      Image(systemName: symbol)
        .font(.system(size: 12.5, weight: .regular))
        .foregroundStyle(text == nil ? Palette.leafInk.opacity(0.32) : Palette.accent)
        .frame(width: 15, height: 18)
      ZStack(alignment: .topLeading) {
        if let text {
          InkedText(plain: text, held: held, fresh: fresh)
            .id(text)
            .font(.system(size: 13.5))
            .foregroundStyle(Palette.leafInk.opacity(0.86))
            .lineLimit(2)
            .lineSpacing(1)
            .transition(.identity)
        } else {
          GeometryReader { frame in
            PencilGuide().frame(width: frame.size.width * guide).padding(.top, 9)
          }
          .transition(.opacity)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: 44, alignment: .top)
    .animation(.easeOut(duration: 0.5), value: text == nil)
  }
}

/// A faint dotted pencil line where words will go.
struct PencilGuide: View {
  var ink = Palette.leafInk.opacity(0.24)

  var body: some View {
    StraightLine()
      .stroke(ink, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.5, 2.5]))
      .frame(height: 1)
  }
}

/// A straight line across the middle of its frame.
struct StraightLine: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.midY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
    return path
  }
}

/// Two rules and a diamond at the head of the page.
private struct Ornament: View {
  var body: some View {
    HStack(spacing: 10) {
      Rectangle().frame(height: Size.hairline)
      Rectangle().frame(width: 6.5, height: 6.5).rotationEffect(.degrees(45))
      Rectangle().frame(height: Size.hairline)
    }
    .foregroundStyle(Palette.leafInk.opacity(0.35))
  }
}

/// Paper: its own color in dark as in light, a little light falling on its top corner, a faint grain, and a
/// soft shadow under it.
struct Paper: View {
  var corner: CGFloat = 3

  var body: some View {
    RoundedRectangle(cornerRadius: corner, style: .continuous)
      .fill(Palette.leaf)
      .overlay {
        RadialGradient(
          colors: [.white.opacity(0.35), .clear], center: UnitPoint(x: 0.2, y: 0), startRadius: 0, endRadius: 360)
      }
      .overlay { Grain().clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous)) }
      .overlay {
        RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(
          .black.opacity(0.1), lineWidth: Size.hairline)
      }
      .shadow(color: Palette.warmShadow.opacity(0.4), radius: 22, y: 20)
      .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
  }
}

/// The grain of paper: hairlines across it, barely there.
private struct Grain: View {
  var body: some View {
    Canvas { context, size in
      var lines = Path()
      var y: CGFloat = 0
      while y < size.height {
        lines.move(to: CGPoint(x: 0, y: y))
        lines.addLine(to: CGPoint(x: size.width, y: y))
        y += 3
      }
      context.stroke(lines, with: .color(.black.opacity(0.018)), lineWidth: 1)
    }
    .allowsHitTesting(false)
  }
}

/// Loci's seal: two amber rings and its name, set at a slant.
struct Seal: View {
  var body: some View {
    ZStack {
      Circle().strokeBorder(Palette.accent.opacity(0.85), lineWidth: 1.5)
      Circle().strokeBorder(Palette.accent.opacity(0.6), lineWidth: Size.hairline).padding(4)
      Text(verbatim: "LOCI")
        .font(.system(size: 11, weight: .semibold, design: .serif))
        .tracking(2)
        .foregroundStyle(Palette.accent)
    }
    .frame(width: 62, height: 62)
    .rotationEffect(.degrees(-14))
    .accessibilityHidden(true)
  }
}

/// The seal coming down from above the page: large and clear, then pressed in place.
struct SealDrop: ViewModifier, Animatable {
  var progress: Double

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    content
      .scaleEffect(2.2 - 1.2 * progress)
      .opacity(min(progress * 1.4, 0.92))
  }
}
