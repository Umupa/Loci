import LociModel
import SwiftUI

/// Where tidying an article stands, as its reader shows it; text that is not an article has none.
struct ArticleTidiness: Equatable {
  let progress: TidyProgress?

  var running: Bool {
    if case .running = progress { true } else { false }
  }
}

/// What the tidy button shows: what it does when clicked, while it runs, once it is done and when it failed.
enum TidyFace: Equatable {
  case ready
  case running(Fraction)
  case tidied
  case failed(String)
  /// Another piece of work on the article is going; tidying waits for it.
  case waiting

  init(progress: TidyProgress?, translating: Bool, justTidied: Bool) {
    switch progress {
    case .running(let share): self = .running(share)
    case .failed(let reason): self = .failed(reason)
    case nil: self = translating ? .waiting : justTidied ? .tidied : .ready
    }
  }

  var clickable: Bool {
    switch self {
    case .ready, .failed: true
    case .running, .tidied, .waiting: false
    }
  }
}

/// The tidy button beside the translate button over an article. Clicking it has a model tidy the article in
/// place; a ring fills while it does, a check shows for a moment when the tidied text is in, and an exclamation
/// mark says it failed, with the reason on hover and another try on click. Without a model to tidy with, it opens
/// the model services.
struct TidyButton: View {
  let progress: TidyProgress?
  let translating: Bool
  let tidy: () -> Void
  @Environment(\.openPlace) private var openPlace
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var hovering = false
  @State private var justTidied = false
  @State private var options: Feed<ModelOptions>?

  private var face: TidyFace { TidyFace(progress: progress, translating: translating, justTidied: justTidied) }

  var body: some View {
    Button {
      guard configured else {
        openPlace(.settings(.models))
        return
      }
      tidy()
    } label: {
      label
    }
    .buttonStyle(PressStyle())
    .disabled(!face.clickable)
    .onHover { hovering = $0 }
    .help(Text(help))
    .accessibilityLabel(Text(help))
    .subscribing(AvailableModels(), into: $options)
    .onChange(of: progress) { before, now in
      guard case .running = before, now == nil else { return }
      withAnimation(reduceMotion ? nil : Motion.quick) { justTidied = true }
    }
    .task(id: justTidied) {
      guard justTidied else { return }
      try? await Task.sleep(for: .seconds(2.5))
      withAnimation(reduceMotion ? nil : Motion.quick) { justTidied = false }
    }
  }

  private var configured: Bool {
    guard let options = options?.value else { return true }
    return options.model(preferring: nil, for: .translation) != nil
  }

  private var label: some View {
    ZStack {
      if case .running(let share) = face {
        Circle().stroke(Palette.line, lineWidth: 1.5)
        Circle()
          .trim(from: 0, to: max(share.value, 0.04))
          .stroke(Palette.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(tint)
        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
    }
    .padding(2)
    .frame(width: Size.iconButton, height: Size.iconButton)
    .background(
      RoundedRectangle(cornerRadius: Radius.row).fill(hovering && face.clickable ? Palette.fillStrong : .clear)
    )
    .contentShape(Rectangle())
  }

  private var symbol: String {
    switch face {
    case .tidied: Symbols.done
    case .failed: Symbols.retry
    case .ready, .running, .waiting: Symbols.tidy
    }
  }

  private var tint: Color {
    switch face {
    case .tidied: Palette.accent
    case .waiting: Palette.inkFaint
    case .ready, .running, .failed: hovering ? Palette.ink : Palette.inkMuted
    }
  }

  private var help: LocalizedStringResource {
    switch face {
    case .ready: configured ? .loci("article.tidy") : .loci("keypoints.configureModels")
    case .running: .loci("article.tidying")
    case .tidied: .loci("article.tidied")
    case .failed(let reason): .loci("article.tidyFailed \(reason)")
    case .waiting: .loci("article.tidyWaits")
    }
  }
}
