import LociModel
import SwiftUI

/// A panel's rows, each a fixed component Loci only fills.
struct PanelRows: View {
  let rows: [PanelRow]
  let actions: PanelActions

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        view(of: row)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private func view(of row: PanelRow) -> some View {
    switch row {
    case .sentence(let text):
      PanelSentence(text: text).padding(.bottom, 14).panelRow()
    case .cells(let cells):
      PanelCells(cells: cells).padding(.bottom, Spacing.m).panelRow()
    case .label(let text):
      Text(verbatim: text).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
        .padding(.top, Spacing.xxs).padding(.bottom, 10)
        .panelRow()
    case .list(let items):
      PanelList(items: items, actions: actions).padding(.bottom, Spacing.m)
    case .prominent(let title, let subtitle):
      PanelProminent(title: title, subtitle: subtitle).padding(.bottom, Spacing.xs).panelRow()
    case .bars(let bars):
      PanelBars(bars: bars).padding(.bottom, Spacing.m).panelRow()
    case .picture(let url, let link):
      PanelPicture(url: url, link: link, open: actions.open).padding(.bottom, Spacing.m).panelRow()
    case .items(let section):
      PanelItemsView(section: section)
    case .quotes(let quotes):
      PanelQuotes(quotes: quotes).padding(.bottom, Spacing.s).panelRow()
    case .line(let chart):
      if let line = PanelLineView(chart: chart) { line.padding(.bottom, Spacing.s).panelRow() }
    case .ruler(let ruler):
      PanelRulerView(ruler: ruler).padding(.bottom, Spacing.m).panelRow()
    case .allocation(let allocation):
      PanelAllocationView(allocation: allocation).padding(.bottom, Spacing.s).panelRow()
    case .heat(let tiles):
      PanelHeat(tiles: tiles).padding(.bottom, Spacing.s).panelRow()
    case .candles(let candles):
      PanelCandlesView(candles: candles).padding(.bottom, Spacing.s).panelRow()
    case .zones(let zones):
      PanelZonesView(zones: zones).padding(.bottom, Spacing.s).panelRow()
    }
  }
}

/// The sentence a panel starts with: faint, with what matters in full ink.
struct PanelSentence: View {
  let text: String

  var body: some View {
    BoldSpans(text).spans.reduce(Text(verbatim: "")) { sentence, span in
      let part = Text(verbatim: span.text)
      return Text(joining: sentence, span.bold ? part.fontWeight(.medium).foregroundStyle(Palette.ink) : part)
    }
    .font(.system(size: 14))
    .lineSpacing(3)
    .foregroundStyle(Palette.ink.opacity(0.5))
    .fixedSize(horizontal: false, vertical: true)
  }
}

private struct PanelCells: View {
  let cells: [PanelCell]
  /// The lines the label and the value take, as the design sets them, so a cell stands 80 tall.
  private static let labelLine: CGFloat = 20
  private static let valueLine: CGFloat = 30

  var body: some View {
    HStack(spacing: Spacing.xs) {
      ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
        VStack(alignment: .leading, spacing: 6) {
          Text(verbatim: cell.label).font(.system(size: 13)).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
            .frame(height: Self.labelLine, alignment: .leading)
          HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
            Text(verbatim: cell.value).font(.system(size: 24, weight: .medium)).kerning(-0.3)
              .foregroundStyle(Palette.ink)
            if let note = cell.note {
              Text(verbatim: note).font(.system(size: 20, weight: .medium)).foregroundStyle(Palette.ink.opacity(0.35))
            }
          }
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .frame(height: Self.valueLine, alignment: .leading)
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.ink.opacity(0.05), in: .rect(cornerRadius: Radius.panelBlock, style: .continuous))
      }
    }
  }
}

private struct PanelProminent: View {
  let title: String
  let subtitle: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(verbatim: title).font(.system(size: 20, weight: .medium)).kerning(-0.2).lineSpacing(3)
        .foregroundStyle(Palette.ink)
      if let subtitle {
        Text(verbatim: subtitle).font(.system(size: 12)).foregroundStyle(Palette.ink.opacity(0.5))
      }
    }
    .padding(Spacing.s)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.ink.opacity(0.05), in: .rect(cornerRadius: Radius.panelBlock, style: .continuous))
  }
}

/// Bars that grow from the left when they first show.
private struct PanelBars: View {
  let bars: [PanelBar]
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var grown = false

  var body: some View {
    VStack(spacing: 9) {
      ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
        HStack(spacing: 10) {
          Text(verbatim: bar.name).font(.system(size: 13)).foregroundStyle(Palette.ink.opacity(0.8))
            .lineLimit(1).truncationMode(.tail)
            .frame(width: 112, alignment: .leading)
          Capsule().fill(Palette.ink.opacity(0.06))
            .overlay(alignment: .leading) {
              GeometryReader { track in
                Capsule().fill(Palette.ink.opacity(0.75))
                  .frame(width: track.size.width * min(max(bar.fraction, 0), 1))
                  .scaleEffect(x: shown ? 1 : 0, anchor: .leading)
              }
            }
            .frame(height: Spacing.xs)
          Text(verbatim: bar.value).font(.system(size: 12)).monospacedDigit()
            .foregroundStyle(Palette.ink.opacity(0.55))
            .frame(width: 44, alignment: .trailing)
        }
      }
    }
    .onAppear {
      withAnimation(reduceMotion ? nil : .timingCurve(0.28, 0.67, 0.32, 1, duration: 0.8)) { grown = true }
    }
  }

  private var shown: Bool { grown || reduceMotion }
}

private struct PanelPicture: View {
  let url: URL
  let link: URL?
  let open: (URL) -> Void
  @Environment(\.webPictures) private var pictures
  @Environment(\.host) private var host

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.panelBlock, style: .continuous)
    Group {
      if let image = pictures?.image(of: url) {
        Image(nsImage: image).resizable().aspectRatio(image.size, contentMode: .fit)
      } else {
        Palette.ink.opacity(0.05).aspectRatio(16 / 9, contentMode: .fit)
      }
    }
    .frame(maxWidth: .infinity)
    .clipShape(shape)
    .contentShape(shape)
    .onTapGesture { if let link { open(link) } }
    .pointerStyle(link == nil ? nil : .link)
    .task(id: url) { await pictures?.load(url, from: host) }
  }
}
