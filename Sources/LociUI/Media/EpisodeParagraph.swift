import LociModel
import SwiftUI

/// One paragraph of an episode's transcript: who speaks and when, then their sentences run together, the one
/// playing washed in amber, highlighted ones banded; the translation under it when both show.
struct EpisodeParagraph: View, Equatable {
  let paragraph: TranscriptParagraph
  /// The words each sentence shows in the paragraph, by index.
  let sentences: [(index: Int, text: String)]
  /// The paragraph's translation, under its words.
  let translation: String?
  let speaker: SpeakerName?
  /// The sentence playing, if it is in this paragraph.
  let playing: Int?
  let chosen: ClosedRange<Int>?
  let noted: Set<Int>
  /// Where its lines are drawn within the transcript.
  let space: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
        if let speaker { speaker }
        Text(verbatim: MediaTime.text(paragraph.start)).font(Typography.mono).foregroundStyle(Palette.inkFaint)
      }
      words
      if let translation { translated(translation) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var words: some View {
    Text(sentences: sentences)
      .font(Typography.episodeTranscript)
      .lineSpacing(6)
      .foregroundStyle(Palette.ink)
      .textRenderer(SentenceMarks(playing: playing, chosen: chosen, noted: noted))
      .fixedSize(horizontal: false, vertical: true)
      .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
        GeometryReader { proxy in
          Color.clear.preference(key: SentenceLines.self, value: SentenceLines.of(layouts, in: proxy, space: space))
        }
      }
      .pointerStyle(.link)
  }

  private func translated(_ text: String) -> some View {
    Text(verbatim: text)
      .font(Typography.transcriptTranslation)
      .lineSpacing(4)
      .foregroundStyle(Palette.inkMuted)
      .fixedSize(horizontal: false, vertical: true)
  }

  nonisolated static func == (left: EpisodeParagraph, right: EpisodeParagraph) -> Bool {
    left.paragraph == right.paragraph && left.sentences.map(\.text) == right.sentences.map(\.text)
      && left.translation == right.translation && left.speaker == right.speaker
      && left.playing == right.playing && left.chosen == right.chosen
      && left.noted == right.noted
  }
}

struct SpeakerName: View, Equatable {
  @Environment(\.host) private var host
  @Environment(\.showFailure) private var showFailure
  let item: EntityID
  let number: Int
  let name: String?
  @State private var editing = false
  @State private var draft = ""

  var body: some View {
    Button {
      draft = name ?? ""
      editing = true
    } label: {
      label.font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
    }
    .buttonStyle(.plain)
    .pointerStyle(.link)
    .help(Text(.loci("transcript.renameSpeaker")))
    .changesData()
    .alert(Text(.loci("transcript.renameSpeaker")), isPresented: $editing) {
      TextField(text: $draft) { Text(.loci("transcript.speakerName")) }
      Button(role: .cancel) {
      } label: {
        Text(.loci("dialog.cancel"))
      }
      Button {
        rename(to: proposedName)
      } label: {
        Text(.loci("item.rename"))
      }
      .keyboardShortcut(.defaultAction)
      .disabled(proposedName.isEmpty || proposedName == name)
      .changesData()
    }
  }

  var label: Text {
    if let name { return Text(verbatim: name) }
    return Text(joining: Text(.loci("transcript.speaker")), Text(verbatim: " \(number)"))
  }

  private var proposedName: String {
    draft.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func rename(to name: String) {
    Task {
      do throws(HostError) {
        _ = try await host.run(RenameSpeaker(item: item, speaker: number, name: name))
      } catch {
        showFailure(error)
      }
    }
  }

  nonisolated static func == (left: SpeakerName, right: SpeakerName) -> Bool {
    left.item == right.item && left.number == right.number && left.name == right.name
  }
}

extension Text {
  /// Sentences run on into one text, each marked with its index.
  init(sentences: [(index: Int, text: String)]) {
    var whole = Text(verbatim: "")
    var before = ""
    for sentence in sentences {
      let part = Text(verbatim: TranscriptParagraph.separator(after: before) + sentence.text)
        .customAttribute(SentenceMark(index: sentence.index))
      let joined: LocalizedStringKey = "\(whole)\(part)"
      whole = Text(joined)
      before = sentence.text
    }
    self = whole
  }
}

/// Which sentence of the transcript some words belong to.
struct SentenceMark: TextAttribute {
  let index: Int
}

/// Draws a paragraph with its sentences marked: the one playing washed in amber, chosen ones washed deeper,
/// highlighted ones banded along the foot of each line.
private struct SentenceMarks: TextRenderer {
  let playing: Int?
  let chosen: ClosedRange<Int>?
  let noted: Set<Int>

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    for line in layout {
      for run in line {
        guard let index = run[SentenceMark.self]?.index else { continue }
        let bounds = run.typographicBounds.rect
        if chosen?.contains(index) == true {
          context.fill(wash(bounds), with: .color(Palette.accent.opacity(0.24)))
        } else if index == playing {
          context.fill(wash(bounds), with: .color(Palette.tint))
        }
        if noted.contains(index) {
          let band = bounds.height * 0.38
          context.fill(
            Path(
              roundedRect: CGRect(x: bounds.minX, y: bounds.maxY - band, width: bounds.width, height: band),
              cornerRadius: 2), with: .color(Palette.mark))
        }
      }
    }
    for line in layout { context.draw(line) }
  }

  private func wash(_ bounds: CGRect) -> Path {
    Path(roundedRect: bounds.insetBy(dx: -3, dy: -2), cornerRadius: 4)
  }
}

/// Where each sentence's words lie in the transcript, line by line.
struct SentenceLines: PreferenceKey {
  static let defaultValue: [Int: [CGRect]] = [:]

  static func reduce(value: inout [Int: [CGRect]], nextValue: () -> [Int: [CGRect]]) {
    value.merge(nextValue()) { $0 + $1 }
  }

  static func of(_ layouts: [Text.LayoutKey.AnchoredLayout], in proxy: GeometryProxy, space: String) -> [Int: [CGRect]]
  {
    let offset = proxy.frame(in: .named(space)).origin
    var lines: [Int: [CGRect]] = [:]
    for anchored in layouts {
      let origin = proxy[anchored.origin]
      for line in anchored.layout {
        for run in line {
          guard let index = run[SentenceMark.self]?.index else { continue }
          let rect = run.typographicBounds.rect.offsetBy(dx: origin.x + offset.x, dy: origin.y + offset.y).integral
          lines[index, default: []].append(rect)
        }
      }
    }
    return lines
  }
}
