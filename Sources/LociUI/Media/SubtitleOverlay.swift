import AppKit
import SwiftUI

/// The sentence playing over the foot of the picture, lettered as the style says. Where it can be moved,
/// dragging it up or down changes how far above the foot it sits, with a guide and the share while dragging.
struct SubtitleOverlay: View {
  let lines: [SubtitleLine]
  let style: SubtitleStyle
  /// The width of picture the letter sizes are given for; a smaller one letters a small picture larger.
  var referenceWidth: CGFloat = 880
  /// Changes how far above the foot the lines sit; `nil` where they stay put.
  var move: ((Int) -> Void)?
  @State private var dragging = false
  /// How far up the lines sat when the drag began.
  @State private var startLift: Int?
  @State private var hovering = false

  var body: some View {
    GeometryReader { frame in
      let scale = frame.size.width / referenceWidth
      let lift = frame.size.height * CGFloat(style.lift) / 100
      ZStack(alignment: .bottom) {
        if dragging {
          guide(width: frame.size.width).offset(y: -lift)
        }
        block(scale: scale)
          .frame(maxWidth: frame.size.width * 0.86)
          .padding(.horizontal, 6 * scale)
          .padding(.vertical, 4 * scale)
          .overlay {
            if move != nil {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                  .white.opacity(dragging ? 0.55 : hovering ? 0.35 : 0), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
          }
          .contentShape(Rectangle())
          .onHover { hovering = $0 }
          .gesture(drag(height: frame.size.height), including: move == nil ? .none : .all)
          .offset(y: -lift)
          .animation(dragging ? nil : Motion.quick, value: style.lift)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
    .allowsHitTesting(move != nil)
  }

  private func block(scale: CGFloat) -> some View {
    VStack(spacing: 4 * scale) {
      ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
        let lettering = line.translated ? style.translation : style.original
        let size = CGFloat(lettering.size) * scale
        Text(verbatim: line.text)
          .font(lettering.font.font(size: size, bold: lettering.bold, heavy: style.preset == .big && index == 0))
          .foregroundStyle(lettering.color.color)
          .multilineTextAlignment(.center)
          .lineSpacing(size * 0.15)
          .modifier(SubtitleBacking(preset: style.preset, size: size, first: index == 0))
      }
    }
  }

  private func guide(width: CGFloat) -> some View {
    ZStack(alignment: .topTrailing) {
      Rectangle()
        .stroke(Self.guideColor, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        .frame(width: width, height: 1)
      Text(verbatim: "\(style.lift)%")
        .font(.system(size: 11, weight: .medium).monospaced())
        .foregroundStyle(Self.guideColor)
        .padding(.trailing, 10)
        .offset(y: -18)
    }
    .frame(width: width, height: 1, alignment: .bottom)
    .allowsHitTesting(false)
  }

  private func drag(height: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 1, coordinateSpace: .global)
      .onChanged { change in
        dragging = true
        let start = startLift ?? style.lift
        startLift = start
        let moved = -Double(change.translation.height) / Double(max(height, 1)) * 100
        let lift = min(
          max(Int((Double(start) + moved).rounded()), SubtitleStyle.lifts.lowerBound), SubtitleStyle.lifts.upperBound)
        if lift != style.lift { move?(lift) }
      }
      .onEnded { _ in
        dragging = false
        startLift = nil
      }
  }

  private static let guideColor = Color(nsColor: NSColor(rgb: 0xFFD27A))
}

/// What sits behind or around each line of a subtitle, by preset.
private struct SubtitleBacking: ViewModifier {
  let preset: SubtitleStyle.Preset
  let size: CGFloat
  let first: Bool

  func body(content: Content) -> some View {
    switch preset {
    case .outline:
      content
        .shadow(color: .black, radius: 1)
        .shadow(color: .black, radius: 1)
        .shadow(color: .black.opacity(0.8), radius: 1.5, y: 1)
    case .band:
      content
        .padding(.horizontal, size * 0.45)
        .padding(.vertical, size * 0.05)
        .background(
          RoundedRectangle(cornerRadius: 4, style: .continuous).fill(
            Color(nsColor: NSColor(rgb: 0x0A0806)).opacity(0.66)))
    case .big:
      content
        .shadow(color: .black.opacity(first ? 0.7 : 0.6), radius: first ? 5 : 2, y: first ? 2 : 1)
        .shadow(color: .black.opacity(0.8), radius: 1)
    case .glass:
      content
        .padding(.horizontal, size * 0.6)
        .padding(.vertical, size * 0.12)
        .background(
          RoundedRectangle(cornerRadius: size * 0.5, style: .continuous)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .overlay(
              RoundedRectangle(cornerRadius: size * 0.5, style: .continuous).fill(
                Color(nsColor: NSColor(rgb: 0x1E1814)).opacity(0.38))
            )
            .overlay(
              RoundedRectangle(cornerRadius: size * 0.5, style: .continuous).strokeBorder(
                .white.opacity(0.25), lineWidth: Size.hairline))
        )
    }
  }
}
