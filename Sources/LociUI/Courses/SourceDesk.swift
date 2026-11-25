import LociModel
import SwiftUI

/// The sources on the desk, two to a row. Each lands as it is found, tilted and dropping from above, and
/// settles with a spring; a ring in its corner fills as Loci reads it and turns into a check. A card opens its
/// original, and under the pointer it lifts and can be struck off. At the foot, a link can be pasted in to add
/// one more.
struct SourceDesk: View {
  let sources: [SourceShown]
  /// Whether more can be added and struck off: not while the course is being written.
  var editable = true
  /// A card caught part way through landing, and one under the pointer, for a snapshot.
  var landing: (id: EntityID, progress: Double)?
  var pointed: EntityID?
  let strike: (SourceShown) -> Void
  let add: (URL) -> Void
  let open: (URL) -> Void

  var body: some View {
    VStack(spacing: 14) {
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
        ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
          SourceCard(
            source: source, pointed: pointed == source.id, editable: editable, strike: { strike(source) }, open: open
          )
          .modifier(
            SourceLanding(
              progress: landing?.id == source.id ? landing?.progress ?? 1 : 1, side: index % 2 == 0 ? -1 : 1)
          )
          .transition(
            .asymmetric(
              insertion: .modifier(
                active: SourceLanding(progress: 0, side: index % 2 == 0 ? -1 : 1),
                identity: SourceLanding(progress: 1, side: 0)),
              removal: .scale(scale: 0.85).combined(with: .offset(y: 10)).combined(with: .opacity)))
        }
      }
      if editable, !sources.isEmpty {
        PasteSource(add: add).changesData().transition(.opacity)
      }
    }
    .frame(width: Size.sourceDesk)
    .animation(Motion.land, value: sources.map(\.id))
  }
}

/// A source card dropping onto the desk: from 70 points up, turned six degrees one way or the other and a little
/// smaller, coming into view in the first part of its fall.
struct SourceLanding: ViewModifier, Animatable {
  var progress: Double
  let side: Double

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let rest = 1 - progress
    content
      .scaleEffect(1 - 0.08 * rest)
      .rotationEffect(.degrees(6 * side * rest))
      .offset(x: 30 * side * rest, y: -70 * rest)
      .opacity(min(progress / 0.6, 1))
  }
}

/// One source: a small picture by its kind, its title in the serif, where it is from, the commit a repository is
/// pinned at, and how much of it Loci has read. Pressed, it opens the original; under the pointer it lifts and a
/// button in its corner strikes it off, and its menu does either.
struct SourceCard: View {
  let source: SourceShown
  var pointed = false
  var editable = true
  let strike: () -> Void
  let open: (URL) -> Void
  @State private var overFace = false
  @State private var overStrike = false

  /// What the card's menu offers.
  enum Choice: Hashable {
    case open(URL)
    case remove
  }

  /// Opening the original when there is one, and removing the source while the sources can change.
  static func menu(for source: SourceShown, editable: Bool) -> [Choice] {
    (source.url.map { [.open($0)] } ?? []) + (editable ? [.remove] : [])
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.answer, style: .continuous)
    let lit = overFace || overStrike || pointed
    let lifted = source.url != nil && lit
    ZStack(alignment: .bottomTrailing) {
      Button {
        if let url = source.url { open(url) }
      } label: {
        face(shape)
          .shadow(
            color: Palette.warmShadow.opacity(lifted ? 0.26 : 0.18), radius: lifted ? 16 : 12, y: lifted ? 13 : 10
          )
          .contentShape(shape)
          .onHover { overFace = $0 }
      }
      .buttonStyle(AnswerPress(scale: source.url == nil ? 1 : 0.98))
      if editable {
        Button(action: strike) {
          Image(systemName: Symbols.cancel)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Palette.inkMuted)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Palette.fillStrong))
            .contentShape(Circle())
            .onHover { overStrike = $0 }
        }
        .buttonStyle(.plain)
        .padding(6)
        .opacity(lit ? 1 : 0)
        .allowsHitTesting(lit)
        .changesData()
        .accessibilityLabel(Text(.loci("course.strikeSource")))
      }
    }
    .offset(y: lifted ? -2 : 0)
    .contextMenu {
      ForEach(Self.menu(for: source, editable: editable), id: \.self) { choice in
        switch choice {
        case .open(let url):
          Button {
            open(url)
          } label: {
            Text(.loci("item.openOriginal"))
          }
        case .remove:
          Button(role: .destructive, action: strike) { Text(.loci("course.strikeSource")) }.changesData()
        }
      }
    }
    .animation(.spring(duration: 0.3, bounce: 0.3), value: lifted)
    .animation(Motion.quick, value: lit)
  }

  private func face(_ shape: RoundedRectangle) -> some View {
    HStack(spacing: 13) {
      SourceThumb(kind: source.kind)
      VStack(alignment: .leading, spacing: 6) {
        Text(serif: source.title, Typography.sourceTitle)
          .lineLimit(2)
          .lineSpacing(1)
          .foregroundStyle(Palette.ink)
        HStack(spacing: 5) {
          Text(verbatim: source.detail).foregroundStyle(Palette.inkMuted)
          if let commit = source.commit {
            Text(verbatim: "@" + commit.prefix(7)).foregroundStyle(Palette.accentInk)
          }
        }
        .font(.system(size: 11, weight: .medium).monospaced())
        .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 12).padding(.leading, 12).padding(.trailing, 28)
    .frame(height: Size.sourceCard)
    .background(shape.fill(Palette.surface))
    .overlay { shape.strokeBorder(Palette.cardEdge, lineWidth: Size.hairline) }
    .overlay(alignment: .topTrailing) { ReadRing(read: source.read).padding(10) }
  }
}

/// How much of a source Loci has read: a ring filling in amber, or an arc going round while how far cannot be
/// told, then a check drawn in where it was.
struct ReadRing: View {
  let read: Double?

  var body: some View {
    let done = (read ?? 0) >= 1
    ZStack {
      Circle().stroke(Palette.fillStrong, lineWidth: 2)
      if let read {
        Circle()
          .trim(from: 0, to: done ? 1 : read)
          .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .opacity(done ? 0 : 1)
      } else {
        LightClock(period: 1.2, held: 0.3) { phase in
          Circle()
            .trim(from: 0, to: 0.28)
            .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(360 * (phase ?? 0) - 90))
        }
      }
      CheckStroke()
        .trim(from: 0, to: done ? 1 : 0)
        .stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        .padding(4)
    }
    .frame(width: 16, height: 16)
    .animation(.easeInOut(duration: 0.6), value: read)
    .animation(Motion.swap.delay(0.1), value: done)
    .accessibilityHidden(true)
  }
}

/// A check mark across its frame.
private struct CheckStroke: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.04))
    path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.12))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
    return path
  }
}

/// The dashed capsule at the foot of the sources: a link pasted or typed in adds a source on Return.
private struct PasteSource: View {
  let add: (URL) -> Void
  @State private var text = ""

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: Symbols.link).font(.system(size: 13))
      TextField(text: $text, prompt: Text(.loci("course.pasteLink")).foregroundStyle(Palette.inkFaint)) {
        Text(.loci("course.pasteLink"))
      }
      .textFieldStyle(.plain)
      .foregroundStyle(Palette.ink)
      .onSubmit {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true
        else { return }
        add(url)
        text = ""
      }
    }
    .font(.system(size: 14))
    .foregroundStyle(Palette.inkFaint)
    .padding(.horizontal, 18)
    .frame(height: 44)
    .overlay {
      Capsule(style: .circular).strokeBorder(
        Palette.inkFaint.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }
  }
}
