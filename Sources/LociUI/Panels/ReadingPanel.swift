import LociModel
import SwiftUI

/// 「接着读」: what was read partway, the latest first, each opening where it was left.
struct ReadingPanel: View {
  let readings: [ReadingNow]
  let actions: PanelActions
  @Environment(\.locale) private var locale

  var body: some View {
    PanelFrame(title: Text(.loci("panels.reading")), menu: PanelMenu.entries(for: .reading(readings))) { _ in
      actions.moveToTop(.reading(readings))
    } marks: {
      LociAvatar(size: Size.siteMark)
    } content: {
      VStack(alignment: .leading, spacing: 0) {
        PanelSentence(text: Self.summary(readings, locale: locale)).padding(.bottom, 14).panelRow()
        VStack(spacing: Spacing.xs) {
          ForEach(readings, id: \.item.id) { reading in
            PanelLine(
              title: reading.item.title, subtitle: subtitle(of: reading.item), progress: reading.progress,
              open: { actions.openItem(reading.item.id) }
            ) {
              Cover(item: reading.item, corner: 9, backdrop: Palette.ink.opacity(0.08))
                .frame(width: Size.panelCover, height: Size.panelCover)
            }
            .panelRow()
          }
        }
        .padding(.bottom, Spacing.m)
      }
    }
  }

  private func subtitle(of item: Item) -> String {
    var kind = SavedItemByline.name(of: ItemKind(item.kind))
    kind.locale = locale
    return [item.site, String(localized: kind)].compactMap { $0 }.joined(separator: " · ")
  }

  /// How much the latest one has left: in minutes when that can be told, or how far along it is.
  static func summary(_ readings: [ReadingNow], locale: Locale) -> String {
    guard let latest = readings.first else { return "" }
    let percent = Int((latest.progress * 100).rounded())
    var words: LocalizedStringResource =
      if let minutes = latest.minutesLeft {
        .loci("panels.readingLeft \(latest.item.title) \(minutes)")
      } else {
        .loci("panels.readingAt \(latest.item.title) \(percent)")
      }
    words.locale = locale
    return String(localized: words)
  }
}

/// Where the panel being made will be, until it is.
struct PanelSkeleton: View {
  let sources: PanelSources
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var sweep = false

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(spacing: Spacing.xs) {
        SiteBadges(sources)
        Text(verbatim: "…").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink.opacity(0.4))
      }
      .padding(.bottom, 6)
      GeometryReader { space in bone.frame(width: space.size.width * 0.78) }.frame(height: 18).padding(
        .bottom, Spacing.xs)
      ForEach(0..<3, id: \.self) { _ in bone.frame(height: 58) }
    }
    .padding(20)
    .background(Palette.surface, in: .rect(cornerRadius: Radius.panel, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        .strokeBorder(Palette.bubbleEdge, lineWidth: Size.hairline)
    )
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { sweep = true }
    }
    .accessibilityHidden(true)
  }

  private var bone: some View {
    RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(Palette.ink.opacity(0.06))
      .overlay {
        GeometryReader { space in
          LinearGradient(
            stops: [
              .init(color: .clear, location: 0.3), .init(color: Palette.ink.opacity(0.08), location: 0.5),
              .init(color: .clear, location: 0.7),
            ], startPoint: .leading, endPoint: .trailing
          )
          .frame(width: space.size.width * 2.5)
          .offset(x: sweep ? -space.size.width * 1.5 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
  }
}
