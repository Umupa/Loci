import LociModel
import SwiftUI

/// What a card can ask of the work on its item.
struct CardActions {
  let pause: (Item) -> Void
  let resume: (Item) -> Void
  /// Cancelling takes the item back out of the library, with the notice that brings it back.
  let cancel: (Item) -> Void
  let fix: (JobLine.Fix, Item) -> Void
}

extension CardActions {
  /// The actions as an item's own page takes them: cancelling deletes the item, the page goes with it, and
  /// the library shows the notice that brings it back.
  @MainActor static func on(
    _ host: any LociModel.Host, fixes: JobFixes, failed: ShowFailure, deletions: Deletions?,
    undoManager: UndoManager?
  ) -> CardActions {
    func run<C: Command>(_ command: C) {
      Task {
        do throws(HostError) {
          _ = try await host.run(command)
        } catch {
          failed(error)
        }
      }
    }
    return CardActions(
      pause: { run(PauseJob(item: $0.id)) }, resume: { run(RetryJob(item: $0.id)) },
      cancel: { item in
        Task {
          do throws(HostError) {
            _ = try await host.run(DeleteItems([item.id]))
            deletions?.happened(1, undoManager: undoManager) { run(RestoreDeleted()) }
          } catch {
            failed(error)
          }
        }
      }, fix: { fixes.apply($0, to: $1) })
  }
}

/// One item in the gallery: its cover, then its title in the serif over two lines and where it comes from.
/// Every cover has the same shape, so the cards line up in rows. While work goes on the cover blurs and its
/// foot carries the stage, its share and the stage ruler; pointing at it offers to pause or carry on and to
/// cancel.
struct GalleryCard: View {
  @Environment(\.standIns) private var standIns
  @Environment(\.covers) private var covers
  let item: Item
  let job: Job?
  let share: Double?
  let chosen: Bool
  let actions: CardActions
  let coverWidth: CGFloat
  /// Set while the title is being renamed: what to do with the new title, `nil` when it was left as it was.
  var renamed: ((String?) -> Void)?
  @State private var pointing = false

  private var state: CardState { CardState(job) }
  private var hovering: Bool { pointing || standIns?.pointedCard == item.id }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      cover
      title.padding(.top, Self.titleGap)
      HStack(spacing: 6) {
        Image(systemName: Symbols.kind(ItemKind(item.kind))).font(.system(size: 11))
        Text(verbatim: byline).lineLimit(1)
      }
      .font(.system(size: 11.5).monospaced())
      .foregroundStyle(Palette.inkMuted)
      .frame(height: Self.bylineHeight, alignment: .topLeading)
      .padding(.top, Self.bylineGap)
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .contentShape(Rectangle())
    .onHover { pointing = $0 }
  }

  /// A book's authors and how far into it the reader is; another item's length and source.
  private var byline: String {
    guard item.kind == .book else { return item.byline }
    let read = share.map { $0.formatted(.percent.precision(.fractionLength(0))) }
    return ([item.authors.joined(separator: ", ")].filter { !$0.isEmpty } + [read].compactMap { $0 })
      .joined(separator: " · ")
  }

  private static let titleGap: CGFloat = 11
  /// Two lines of the title, which a card leaves room for whether it uses them or not.
  private static let titleHeight: CGFloat = 40
  private static let bylineGap: CGFloat = 6
  private static let bylineHeight: CGFloat = 15

  /// How tall every card `width` wide is, so a row of them lines up.
  static func height(at width: CGFloat) -> CGFloat {
    width / coverRatio + titleGap + titleHeight + bylineGap + bylineHeight
  }

  /// The shape of every cover in the gallery: a podcast's square art sits inside it on a wash of its colors.
  static let coverRatio: CGFloat = 16 / 10

  @ViewBuilder private var art: some View {
    let picture = Cover(item: item, corner: 0, squareInset: 0.09, squareCorner: 6, edge: coverWidth)
    if state.isBusy {
      let softened = item.kind != .article || covers?.image(of: item.id) == nil
      picture
        .blur(radius: softened ? 9 : 0)
        .scaleEffect(softened ? 1.12 : 1)
        .saturation(saturation)
        .brightness(brightness)
        .drawingGroup()
    } else {
      picture
    }
  }

  private var cover: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.galleryCover, style: .continuous)
    return
      art
      .frame(height: coverWidth / Self.coverRatio)
      .overlay {
        if state.isBusy {
          let shade: Double = articleFailure == nil ? 0 : 0.32
          LinearGradient(
            stops: [
              .init(color: .black.opacity(shade), location: 0.4), .init(color: .black.opacity(0.45), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
        }
      }
      .overlay(alignment: .bottom) { if !state.isBusy { ProgressLine(share: share) } }
      .clipShape(shape)
      .overlay(alignment: .bottom) { foot }
      .overlay(alignment: .topTrailing) {
        if state.pausable, hovering { hoverButtons.transition(.opacity) }
      }
      .animation(Motion.quick, value: hovering)
      .overlay { if case .needs(let fix) = state { center(fix) } }
      .overlay { shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline) }
      .overlay { if chosen { shape.strokeBorder(Palette.accent, lineWidth: 3) } }
      .background {
        SoftShadow(shape: shape, color: Palette.warmShadow, opacity: 0.1, radius: 12, y: 6, steps: 4)
        SoftShadow(shape: shape, opacity: 0.08, radius: 1.5, y: 1, steps: 2)
      }
      .amberGlow(state.glows, corner: Radius.galleryCover)
  }

  private var saturation: Double {
    switch state {
    case .ready: 1
    case .queued, .working: 0.85
    case .paused: 0.3
    case .needs: 0.5
    }
  }

  private var brightness: Double {
    switch state {
    case .ready: 0
    case .queued, .working: -0.04
    case .paused: -0.1
    case .needs: -0.14
    }
  }

  /// Along the foot of a busy cover: the stage and its share, over the stage ruler.
  @ViewBuilder private var foot: some View {
    if let job, state.isBusy {
      VStack(alignment: .leading, spacing: 6) {
        if let words = footWords {
          HStack(spacing: Spacing.xs) {
            words.name.font(.system(size: 11.5, weight: .semibold))
            Spacer(minLength: 0)
            if let share = words.share {
              Text(verbatim: StageRuler.percent(share)).font(.system(size: 11.5, weight: .semibold).monospaced())
            }
          }
          .foregroundStyle(Palette.onCover)
          .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        StageRuler(segments: StageRuler.segments(of: job, kind: item.kind), size: .cover)
      }
      .padding(.horizontal, 10)
      .padding(.bottom, 9)
    }
  }

  private var footWords: (name: Text, share: Fraction?)? {
    switch state {
    case .working(let stage, let progress): (Text(stage.name), progress)
    case .queued: (Text(.loci("job.queued")), nil)
    case .paused(let progress): (Text(.loci("job.paused")), progress)
    case .ready, .needs: nil
    }
  }

  private var hoverButtons: some View {
    HStack(spacing: 6) {
      if case .paused = state {
        GlassRound(symbol: "play.fill", size: 26) { actions.resume(item) }
      } else {
        GlassRound(symbol: "pause.fill", size: 26) { actions.pause(item) }
      }
      GlassRound(symbol: "xmark", size: 26) { actions.cancel(item) }
    }
    .padding(8)
  }

  private var articleFailure: JobLine.Problem? {
    guard item.kind == .article, case .action(_, let problem) = JobLine(job) else { return nil }
    return problem
  }

  @ViewBuilder private func center(_ fix: JobLine.Fix) -> some View {
    if let problem = articleFailure, let source = item.source {
      VStack(spacing: 6) {
        Text(problem.summary)
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(Palette.onCover)
          .lineLimit(1)
        HStack(spacing: 6) {
          fixButton(fix)
          Link(destination: source) {
            Image(systemName: Symbols.external)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(Palette.onCover)
              .frame(width: 28, height: 28)
              .glassEffect(.clear, in: .circle)
          }
          .buttonStyle(PressStyle())
          .help(Text(.loci("job.openInBrowser")))
          .accessibilityLabel(Text(.loci("job.openInBrowser")))
        }
      }
      .padding(8)
    } else {
      fixButton(fix)
    }
  }

  private func fixButton(_ fix: JobLine.Fix) -> some View {
    Button {
      actions.fix(fix, item)
    } label: {
      fix.label
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(Palette.onCover)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Capsule().fill(.white.opacity(0.16)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: Size.hairline))
        .glassEffect(.clear, in: .capsule)
    }
    .buttonStyle(PressStyle())
    .changesData(fix.changesData)
  }

  @ViewBuilder private var title: some View {
    if let renamed {
      TitleField(title: item.title, font: Typography.cardTitle.latin, ink: Palette.ink, done: renamed)
    } else {
      Text(serif: item.title, Typography.cardTitle)
        .foregroundStyle(Palette.ink)
        .lineLimit(2)
        .lineSpacing(1)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// The item's cover in the wide frames of the task dock and the preparation page.
struct GalleryArt: View {
  let item: Item

  var body: some View {
    Cover(item: item, corner: 0, squareInset: 0.1)
  }
}

/// A small round button of dark glass, for use over a cover.
struct GlassRound: View {
  let symbol: String
  let size: CGFloat
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: size * 0.44, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Circle().fill(Color(white: 0.1, opacity: 0.42)))
        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: Size.hairline))
        .glassEffect(.clear, in: .circle)
        .contentShape(Circle())
    }
    .buttonStyle(PressStyle())
    .changesData()
  }
}
