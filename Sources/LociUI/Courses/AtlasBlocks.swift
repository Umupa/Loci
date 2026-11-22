import LociModel
import SwiftUI

/// A part of the atlas, drawn by its kind.
struct AtlasBlockView: View {
  let block: AtlasBlock

  var body: some View {
    switch block {
    case .figures(let figures): AtlasFiguresView(figures: figures)
    case .flow(let flow):
      VStack(alignment: .leading, spacing: 0) {
        AtlasHead(title: flow.title, lede: flow.lede, lessons: flow.lessons)
        AtlasFlowRow(steps: flow.steps)
        if let aside = flow.aside { AtlasAside(text: aside).padding(.top, 14) }
      }
    case .layers(let layers):
      VStack(alignment: .leading, spacing: 0) {
        AtlasHead(title: layers.title, lede: layers.lede, lessons: layers.lessons)
        AtlasSideBySide(spacing: 26) {
          ForEach(Array(layers.columns.enumerated()), id: \.offset) { _, column in AtlasColumnView(column: column) }
        }
      }
    case .cards(let cards):
      VStack(alignment: .leading, spacing: 0) {
        AtlasHead(title: cards.title, lede: cards.lede, lessons: cards.lessons)
        AtlasSideBySide(spacing: 18) {
          ForEach(Array(cards.cards.enumerated()), id: \.offset) { _, card in AtlasCardView(card: card) }
        }
      }
    case .dive(let dive): AtlasDiveView(dive: dive)
    case .table(let table): AtlasTableView(table: table)
    }
  }
}

/// A section's title with the beads of the lessons behind it at the far end, and its one-line lede.
struct AtlasHead: View {
  let title: AtlasText
  let lede: AtlasText?
  let lessons: [Lesson.ID]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        AtlasInline.text(title, size: 21, serif: true, weight: .semibold)
          .foregroundStyle(Palette.ink)
        Spacer(minLength: Spacing.m)
        AtlasBeads(ids: lessons)
      }
      if let lede {
        AtlasInline.text(lede, size: 14, serif: true)
          .foregroundStyle(Palette.inkMuted)
      }
    }
    .padding(.bottom, 20)
  }
}

/// Children side by side in equal widths where the page is wide enough, else one under another.
struct AtlasSideBySide<Content: View>: View {
  var spacing: CGFloat = 16
  @ViewBuilder let content: () -> Content
  @State private var wide = true

  var body: some View {
    Group {
      if wide {
        HStack(alignment: .top, spacing: spacing) { content() }.fixedSize(horizontal: false, vertical: true)
      } else {
        VStack(alignment: .leading, spacing: spacing) { content() }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onGeometryChange(for: Bool.self) {
      $0.size.width >= Size.atlasSideBySide
    } action: {
      wide = $0
    }
  }
}

/// The quantities a subject turns on, between two rules.
struct AtlasFiguresView: View {
  let figures: [AtlasFigure]

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(Array(figures.enumerated()), id: \.offset) { index, figure in
        VStack(alignment: .leading, spacing: 0) {
          AtlasInline.text(figure.title, size: 15, serif: true, weight: .semibold)
            .foregroundStyle(Palette.inkMuted)
          AtlasInline.text(figure.value, size: 21, serif: true, weight: .semibold)
            .foregroundStyle(Palette.ink)
            .padding(.top, 10)
          if let note = figure.note {
            AtlasInline.text(note, size: 12.5)
              .foregroundStyle(Palette.inkMuted)
              .lineSpacing(3)
              .padding(.top, 6)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .padding(.leading, index == 0 ? 0 : 18)
        .padding(.trailing, 18)
        .overlay(alignment: .leading) {
          if index > 0 { Rectangle().fill(Palette.line).frame(width: Size.hairline) }
        }
      }
    }
    .overlay(alignment: .top) { Rectangle().fill(Palette.ink.opacity(0.85)).frame(height: 1) }
    .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline) }
  }
}

/// Steps in a row joined by arrows, or one under another where the row does not fit.
struct AtlasFlowRow: View {
  let steps: [AtlasStep]

  @State private var wide = true

  var body: some View {
    Group {
      if wide {
        HStack(alignment: .top, spacing: 0) {
          ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            if index > 0 { AtlasArrow(axis: .horizontal) }
            AtlasStepBox(step: step).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          }
        }
        .fixedSize(horizontal: false, vertical: true)
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            if index > 0 { AtlasArrow(axis: .vertical) }
            AtlasStepBox(step: step)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onGeometryChange(for: Bool.self) {
      $0.size.width >= Size.atlasStep * CGFloat(steps.count)
    } action: {
      wide = $0
    }
  }
}

/// One box of a flow: a small label over its title, a few points, and the beads of its lessons.
struct AtlasStepBox: View {
  let step: AtlasStep

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let label = step.label {
        AtlasInline.text(label, size: 11, weight: .semibold)
          .foregroundStyle(Palette.inkFaint)
          .padding(.bottom, 4)
      }
      AtlasInline.text(step.title, size: 14.5, serif: true, weight: .semibold)
        .foregroundStyle(Palette.ink)
      if !step.points.isEmpty { AtlasPoints(points: step.points, size: 12.5).padding(.top, 8) }
      if !step.lessons.isEmpty { AtlasBeads(ids: step.lessons).padding(.top, 10) }
    }
    .padding(.horizontal, 13).padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(AtlasBox(key: step.key))
  }
}

/// The ground of a box: faint ink, or amber for the one the rest turns on.
struct AtlasBox: View {
  var key = false
  var radius: CGFloat = 12

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    shape.fill(key ? Palette.tint : Palette.fill)
      .overlay { shape.strokeBorder(key ? Palette.accentLine : Palette.lineStrong, lineWidth: key ? 1 : Size.hairline) }
  }
}

/// Short lines, each after a dash.
struct AtlasPoints: View {
  let points: [AtlasText]
  var size: CGFloat = 13

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(points.enumerated()), id: \.offset) { _, point in
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Rectangle().fill(Palette.inkMuted).frame(width: 4, height: 1).alignmentGuide(.firstTextBaseline) { _ in 3 }
          AtlasInline.text(point, size: size)
            .foregroundStyle(Palette.ink.opacity(0.74))
            .lineSpacing(2.5)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}

/// The arrow between two steps.
struct AtlasArrow: View {
  let axis: Axis

  var body: some View {
    Image(systemName: axis == .horizontal ? "arrow.right" : "arrow.down")
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(Palette.inkMuted)
      .frame(width: axis == .horizontal ? 26 : nil, height: axis == .vertical ? 22 : nil)
      .frame(maxHeight: axis == .horizontal ? .infinity : nil)
      .frame(maxWidth: axis == .vertical ? .infinity : nil)
  }
}

/// A line under a flow for the path that goes around it, on a dashed rule.
struct AtlasAside: View {
  let text: AtlasText

  var body: some View {
    ZStack {
      Rectangle()
        .stroke(Palette.inkFaint, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        .frame(height: 1)
      AtlasInline.text(text, size: 13, serif: true)
        .italic()
        .foregroundStyle(Palette.inkMuted)
        .padding(.horizontal, 12)
        .background(Palette.canvas)
    }
  }
}
