import LociModel
import SwiftUI

/// The button over a web page that puts what it holds into the library: the library's books, filled once the
/// page is kept, with a small amber number when there is more on the page to choose from. From the click on, a
/// ring goes round it while what was kept is saved, and an amber mark stays on it when it was not.
struct KeepButton: View {
  let finds: PageFinds
  let choosing: Bool
  var keeping: Keeping.State?
  let action: () -> Void
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: filled ? Symbols.libraryKept : Symbols.library)
        .font(.system(size: saving ? 10.5 : 14))
        .foregroundStyle(Palette.accent)
        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace.downUp))
        .frame(width: Size.iconButton, height: Size.iconButton)
        .overlay { if case .saving(let share) = keeping { KeepRing(share: share).padding(5) } }
        .background(Circle().fill(hovering || choosing ? Palette.fillStrong : .clear))
        .overlay(alignment: .topTrailing) {
          if stopped {
            Image(systemName: Symbols.retry)
              .font(.system(size: 8, weight: .heavy))
              .foregroundStyle(Palette.onAccent)
              .frame(width: 13, height: 13)
              .background(Circle().fill(Palette.accent))
              .overlay(Circle().strokeBorder(Palette.menuFace, lineWidth: 1.5).padding(-1.5))
              .offset(x: 4, y: -1)
              .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
          } else if keeping == nil, let count = finds.count {
            Text(verbatim: "\(count)")
              .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
              .foregroundStyle(Palette.onAccent)
              .padding(.horizontal, 3)
              .frame(minWidth: 13, minHeight: 13)
              .background(Capsule().fill(Palette.accent))
              .overlay(Capsule(style: .circular).strokeBorder(Palette.menuFace, lineWidth: 1.5).padding(-1.5))
              .offset(x: 4, y: -1)
              .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
          }
        }
        .contentShape(Circle())
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
    .animation(reduceMotion ? nil : Motion.quick, value: finds.count)
    .animation(reduceMotion ? nil : Motion.quick, value: keeping)
    .help(Text(title))
    .accessibilityLabel(Text(title))
    .accessibilityValue(finds.count.map { Text(verbatim: "\($0)") } ?? Text(verbatim: ""))
  }

  private var title: LocalizedStringResource {
    switch keeping {
    case .saving: .loci("overlay.saving")
    case .saved: .loci("overlay.inLibrary")
    case .stopped, .refused: .loci("overlay.notSaved")
    case nil: finds.kept && finds.count == nil ? .loci("overlay.inLibrary") : .loci("overlay.save")
    }
  }

  private var saving: Bool {
    if case .saving = keeping { true } else { false }
  }

  private var stopped: Bool {
    switch keeping {
    case .stopped, .refused: true
    case .saving, .saved, nil: false
    }
  }

  private var filled: Bool {
    switch keeping {
    case .saved: true
    case .saving, .stopped, .refused: false
    case nil: finds.kept
    }
  }
}

/// Round the library button while what was kept is saved: filled as far as it has got, or turning when that
/// cannot be told.
private struct KeepRing: View {
  let share: Fraction?
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var turned = false

  var body: some View {
    ZStack {
      Circle().stroke(Palette.line, lineWidth: 1.5)
      Circle()
        .trim(from: 0, to: share.map { max($0.value, 0.06) } ?? 0.28)
        .stroke(Palette.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        .rotationEffect(.degrees(share == nil && turned ? 270 : -90))
        .animation(
          share == nil && !reduceMotion ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
          value: turned)
    }
    .onAppear { turned = !reduceMotion }
    .accessibilityHidden(true)
  }
}

/// What the page holds, under its button: the page first, then the videos and papers it links to, each with a
/// check; those not in the library yet start checked, even when the library or the page reports them late. A
/// long list has a switch that checks them all, or clears them all once all are checked. Resting the pointer on a row rings that link on the page.
struct KeepList: View {
  let finds: PageFinds
  let site: String?
  let keep: ([PageFinds.Find]) -> Void
  let point: (PageFinds.Find?) -> Void
  @State private var unchecked: Set<URL> = []
  @State private var pointed: URL?

  private var chosen: [PageFinds.Find] { finds.left.filter { !unchecked.contains($0.url) } }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 0) {
          ForEach(finds.all) { find in
            row(find)
            if find.kind == .page, finds.all.count > 1 {
              Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline).padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
            }
          }
        }
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(maxHeight: 380)
      .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: Spacing.xs) {
        if finds.left.count > Self.longList {
          Button {
            unchecked = Self.toggled(unchecked, of: finds)
          } label: {
            Text(chosen.count == finds.left.count ? .loci("browser.selectNone") : .loci("browser.selectAll"))
          }
          .buttonStyle(QuietButtonStyle())
        }
        Button {
          keep(chosen)
        } label: {
          Text(.loci("overlay.saveSome \(chosen.count)"))
        }
        .buttonStyle(AmberButtonStyle(fills: true))
        .disabled(chosen.isEmpty)
      }
      .padding(.horizontal, 3)
      .padding(.top, Spacing.xxs)
      .padding(.bottom, 3)
    }
    .padding(5)
    .frame(width: Size.keepList)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.floating)
        .shadow(color: .black.opacity(0.28), radius: 25, y: 18)
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
    )
    .onHover { inside in
      if !inside {
        pointed = nil
        point(nil)
      }
    }
  }

  /// More rows than this to choose from, and the list has its switch.
  static let longList = 5

  /// Every row left when any is unchecked; none when all are checked. Takes and gives the rows unchecked.
  nonisolated static func toggled(_ unchecked: Set<URL>, of finds: PageFinds) -> Set<URL> {
    let left = finds.left.map(\.url)
    return left.contains(where: unchecked.contains) ? [] : Set(left)
  }

  private func row(_ find: PageFinds.Find) -> some View {
    let kept = find.inLibrary != nil
    let on = !kept && !unchecked.contains(find.url)
    return Button {
      if on { unchecked.insert(find.url) } else { unchecked.remove(find.url) }
    } label: {
      HStack(spacing: 10) {
        Box(on: on, kept: kept)
        thumbnail(find).frame(width: 48)
        Text(verbatim: find.title)
          .font(.system(size: 12.5, weight: .medium))
          .foregroundStyle(kept ? Palette.inkFaint : Palette.ink)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, Spacing.xs)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(pointed == find.url && !kept ? Palette.fill : .clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
    .disabled(kept)
    .onHover { inside in
      guard inside else { return }
      pointed = find.url
      point(find)
    }
  }

  @ViewBuilder private func thumbnail(_ find: PageFinds.Find) -> some View {
    switch find.kind {
    case .page:
      if let site { SiteBadge(site: site, size: 27, ring: .clear) }
    case .video:
      AsyncImage(url: find.thumbnail) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        Palette.coverBackdrop
      }
      .frame(width: 48, height: 27)
      .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
      )
    case .paper:
      PaperSheet()
    }
  }
}

/// A square check in amber; a kept row shows only a faint tick.
private struct Box: View {
  let on: Bool
  let kept: Bool

  var body: some View {
    ZStack {
      if kept {
        Image(systemName: Symbols.done).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.inkFaint)
      } else if on {
        RoundedRectangle(cornerRadius: 4.5, style: .continuous).fill(Palette.accent)
        Image(systemName: Symbols.done).font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.onAccent)
      } else {
        RoundedRectangle(cornerRadius: 4.5, style: .continuous).fill(Palette.thumb)
        RoundedRectangle(cornerRadius: 4.5, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: 1)
      }
    }
    .frame(width: 16, height: 16)
  }
}

/// A small page with lines of text on it, for a paper.
private struct PaperSheet: View {
  var body: some View {
    VStack(spacing: 2.5) {
      ForEach(0..<5, id: \.self) { line in
        Capsule().fill(Palette.paperInkMuted.opacity(line == 0 ? 0.7 : 0.35)).frame(height: line == 0 ? 1.5 : 1)
      }
    }
    .padding(.horizontal, 4)
    .frame(width: 21, height: 27)
    .background(RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Palette.paper))
    .overlay(
      RoundedRectangle(cornerRadius: 2.5, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
    )
  }
}
