import LociModel
import SwiftUI

/// One column of stacked layers: its title and note, the layers from the top down with the one it is about in
/// amber, and what that means under them.
struct AtlasColumnView: View {
  let column: AtlasColumn

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        AtlasInline.text(column.title, size: 16, serif: true, weight: .semibold)
          .foregroundStyle(Palette.ink)
        Spacer(minLength: Spacing.xs)
        if let note = column.note {
          AtlasInline.text(note, size: 12).foregroundStyle(Palette.inkFaint)
        }
      }
      .padding(.bottom, 4)
      ForEach(Array(column.layers.enumerated()), id: \.offset) { _, layer in
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
          AtlasInline.text(layer.text, size: 12.5)
            .foregroundStyle(Palette.ink.opacity(layer.marked ? 1 : 0.78))
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          if layer.marked { Circle().fill(Palette.accent).frame(width: 7, height: 7) }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(AtlasBox(key: layer.marked, radius: 9))
      }
      if let verdict = column.verdict {
        AtlasInline.text(verdict, size: 13, serif: true)
          .foregroundStyle(Palette.inkMuted)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 6)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

/// A card: a small label over its title, its points, and under a dashed rule how it breaks.
struct AtlasCardView: View {
  let card: AtlasCard

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let label = card.label {
        AtlasInline.text(label, size: 12.5, weight: .semibold).foregroundStyle(Palette.inkFaint)
      }
      AtlasInline.text(card.title, size: 19, serif: true, weight: .semibold)
        .foregroundStyle(Palette.ink)
        .padding(.top, 2)
      AtlasPoints(points: card.points).padding(.top, 12)
      if let breaks = card.breaks {
        DashedRule().padding(.vertical, 12)
        AtlasInline.text(breaks, size: 13, serif: true)
          .italic()
          .foregroundStyle(Palette.inkMuted)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
      if !card.lessons.isEmpty { AtlasBeads(ids: card.lessons).padding(.top, 14) }
    }
    .padding(18)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(AtlasBox(radius: 14))
  }
}

/// What one lesson taught: its flow, and the few things to keep from it.
struct AtlasDiveView: View {
  let dive: AtlasDive

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
        AtlasInline.text(dive.title, size: 17, serif: true, weight: .semibold).foregroundStyle(Palette.ink)
        if let lede = dive.lede {
          AtlasInline.text(lede, size: 13.5, serif: true).foregroundStyle(Palette.inkMuted).lineLimit(1)
        }
        Spacer(minLength: Spacing.s)
        AtlasBeads(ids: [dive.lesson])
      }
      AtlasFlowRow(steps: dive.steps).padding(.top, 16)
      if !dive.keep.isEmpty {
        AtlasSideBySide(spacing: 12) {
          ForEach(Array(dive.keep.enumerated()), id: \.offset) { _, line in
            AtlasInline.text(line, size: 12.5)
              .foregroundStyle(Palette.ink.opacity(0.8))
              .lineSpacing(2.5)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.horizontal, 12).padding(.vertical, 10)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
              .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.fill))
          }
        }
        .padding(.top, 16)
      }
    }
    .padding(.horizontal, 24).padding(.vertical, 22)
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
    }
  }
}

/// A lesson read whose part Loci has not drawn yet: its title in pencil, in a dashed frame.
struct AtlasAdding: View {
  let lesson: AtlasLesson

  var body: some View {
    HStack(spacing: Spacing.s) {
      Text(serif: lesson.title, Serif.Face(size: 16))
        .foregroundStyle(Palette.inkFaint)
        .lineLimit(1)
      Spacer(minLength: Spacing.s)
      Circle().fill(Palette.accent).frame(width: 7, height: 7)
    }
    .padding(.horizontal, 24).padding(.vertical, 18)
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(Palette.inkFaint, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }
  }
}

/// A comparison: one column per system, one row per choice; rows where they differ most in amber, a cell not
/// read about yet a pencil dash.
struct AtlasTableView: View {
  let table: AtlasTable

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      AtlasHead(title: table.title, lede: table.lede, lessons: table.lessons)
      Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
        GridRow {
          Color.clear.frame(width: 1, height: 1).gridColumnAlignment(.leading)
          ForEach(Array(table.columns.enumerated()), id: \.offset) { _, column in
            AtlasInline.text(column, size: 12.5, weight: .semibold)
              .foregroundStyle(Palette.inkMuted)
              .padding(.horizontal, 12).padding(.bottom, 10)
          }
        }
        GridRow {
          Rectangle().fill(Palette.ink.opacity(0.85)).frame(height: 1).gridCellColumns(table.columns.count + 1)
        }
        ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
          if index > 0 {
            GridRow {
              Rectangle().fill(Palette.line).frame(height: Size.hairline).gridCellColumns(table.columns.count + 1)
            }
          }
          GridRow {
            HStack(spacing: Spacing.xs) {
              AtlasInline.text(row.label, size: 13.5, serif: true, weight: .semibold).foregroundStyle(Palette.ink)
              AtlasBeads(ids: row.lessons)
            }
            .padding(.vertical, 11).padding(.leading, row.key ? 10 : 0).padding(.trailing, Spacing.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(alignment: .leading) { if row.key { Palette.accent.frame(width: 2) } }
            ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
              Group {
                if let cell {
                  AtlasInline.text(cell, size: 13).foregroundStyle(Palette.ink.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                  DashedRule().frame(width: 64).padding(.top, 9)
                }
              }
              .padding(.horizontal, 12).padding(.vertical, 11)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
          }
          .background(row.key ? Palette.tint.opacity(0.5) : .clear)
        }
      }
    }
  }
}

/// A dashed hairline in pencil.
struct DashedRule: View {
  var body: some View {
    Rectangle()
      .stroke(Palette.inkFaint, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
      .frame(height: 1)
  }
}
