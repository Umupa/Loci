import LociModel
import Markdown
import SwiftUI

/// An article cut down to its key points: each key passage on an amber wash with its number in the margin, and
/// between them a line saying how many passages are folded away, which opens them when clicked.
struct KeyPassagesReader: View {
  let title: String?
  let markdown: String
  let points: [KeyPoint]
  /// The key point to bring into view and flash, and a serial that changes each time it is asked again.
  let revealed: (number: Int, serial: Int)?
  @State private var open: Set<Int> = []
  @State private var flashing: Int?

  var body: some View {
    let parts = KeyPassageLayout(markdown: markdown, points: points).parts
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let title {
            Text(serif: title, Serif.Face(size: 32, weight: .semibold))
              .foregroundStyle(Palette.ink)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.bottom, 6)
          }
          ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
            switch part {
            case .key(let number, let text):
              key(number, text).id(number)
            case .folded(let texts):
              if open.contains(index) {
                ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
                  passage(text).foregroundStyle(Palette.inkMuted)
                }
              } else {
                fold(texts.count) { withAnimation(Motion.standard) { _ = open.insert(index) } }
              }
            }
          }
        }
        .frame(maxWidth: Typography.readingWidth, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.top, 64)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity)
      }
      .onChange(of: revealed?.serial) {
        guard let revealed else { return }
        withAnimation(Motion.standard) { proxy.scrollTo(revealed.number, anchor: .center) }
        flash(revealed.number)
      }
    }
  }

  private func key(_ number: Int, _ text: String) -> some View {
    passage(text)
      .foregroundStyle(Palette.ink)
      .padding(.horizontal, Spacing.m)
      .padding(.vertical, Spacing.s)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
          .fill(flashing == number ? Palette.flash : Palette.tint)
      )
      .overlay(alignment: .topLeading) {
        Text(verbatim: "\(number)")
          .font(.system(size: 12, weight: .bold).monospaced())
          .foregroundStyle(Palette.accentInk)
          .offset(x: -30, y: 14)
      }
      .padding(.horizontal, -Spacing.m)
  }

  private func passage(_ text: String) -> some View {
    Text(Self.inline(text))
      .font(Font(NSFont.serif(ofSize: 17)))
      .lineSpacing(17 * 0.4)
      .fixedSize(horizontal: false, vertical: true)
      .textSelection(.enabled)
  }

  private func fold(_ count: Int, open: @escaping () -> Void) -> some View {
    Button(action: open) {
      HStack(spacing: 10) {
        Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline)
        Text(.loci("keypoints.folded \(count)")).font(.system(size: 11.5).monospaced()).foregroundStyle(
          Palette.inkFaint
        )
        .fixedSize()
        Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline)
      }
      .frame(height: 20)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func flash(_ number: Int) {
    flashing = number
    Task {
      try? await Task.sleep(for: Motion.flashHold)
      withAnimation(Motion.flashFade) { flashing = nil }
    }
  }

  /// A heading or paragraph's Markdown as styled words, without the heading marks.
  static func inline(_ markdown: String) -> AttributedString {
    let bare = markdown.replacing(/^#{1,6}\s+/, with: "")
    return (try? AttributedString(markdown: bare)) ?? AttributedString(bare)
  }
}

/// The passages of an article in order, as key ones and runs of folded ones between them.
struct KeyPassageLayout {
  enum Part: Equatable {
    case key(number: Int, text: String)
    case folded([String])
  }

  let parts: [Part]

  /// The title heading stays out; a key point whose passage is no longer in the text is left out.
  init(markdown: String, points: [KeyPoint]) {
    let passages = Self.passages(of: markdown)
    var keys: [Int: Int] = [:]
    for (order, point) in points.enumerated() {
      if let text = point.passage?.text, let index = passages.firstIndex(of: text) { keys[index] = order + 1 }
    }
    var parts: [Part] = []
    var folded: [String] = []
    for (index, text) in passages.enumerated() {
      if let number = keys[index] {
        if !folded.isEmpty { parts.append(.folded(folded)) }
        folded = []
        parts.append(.key(number: number, text: text))
      } else if index > 0 || !text.hasPrefix("# ") {
        folded.append(text)
      }
    }
    if !folded.isEmpty { parts.append(.folded(folded)) }
    self.parts = parts
  }

  /// Where a passage's words begin and end in the plain text of the article, found by their first words.
  static func range(of passage: String, in plain: String) -> NSRange? {
    let words = plainText(of: passage)
    let start = String(words.prefix(80))
    guard !start.isEmpty, let found = plain.range(of: start) else { return nil }
    let whole = plain.range(of: words, range: found.lowerBound..<plain.endIndex) ?? found
    return NSRange(whole, in: plain)
  }

  private static func plainText(of passage: String) -> String {
    var text = ""
    for child in Document(parsing: passage).children {
      if let block = child as? (any InlineContainer) { text += block.plainText }
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Each heading and each paragraph with words in it, as the Markdown the host sends to be translated.
  static func passages(of markdown: String) -> [String] {
    var passages: [String] = []
    var seen: Set<String> = []
    func visit(_ markup: any Markup) {
      switch markup {
      case is Heading:
        add(markup)
      case let paragraph as Paragraph:
        let plain = paragraph.plainText
        let picture = paragraph.childCount == 1 && paragraph.child(at: 0) is Markdown.Image
        if !picture, plain.contains(where: \.isLetter), Formula.display(in: plain) == nil { add(paragraph) }
      case is CodeBlock, is HTMLBlock, is Markdown.Table, is ThematicBreak:
        break
      default:
        for child in markup.children { visit(child) }
      }
    }
    func add(_ markup: any Markup) {
      let source = MarkdownRenderer.source(of: markup)
      if !source.isEmpty, seen.insert(source).inserted { passages.append(source) }
    }
    for child in Document(parsing: markdown).children { visit(child) }
    return passages
  }
}
