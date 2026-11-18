import LociModel
import SwiftUI
import Textual

/// Loci's Soul: the core the person may rewrite, beside the traits it grew on its own, newest first.
struct SoulTab: View {
  @Environment(\.host) private var host
  @Environment(\.showFailure) private var showFailure
  let soul: Soul
  @State private var editing: String?

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.xxl) {
      VStack(alignment: .leading, spacing: 10) {
        if let editing {
          editor(editing)
        } else {
          SoulCore(markdown: soul.core)
          PageButton(title: .loci("loci.edit")) { editing = soul.core }.changesData()
        }
      }
      .frame(maxWidth: 580, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      TraitTimeline(traits: soul.traits).frame(width: 300, alignment: .leading)
    }
  }

  private func editor(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      TextEditor(text: Binding(get: { text }, set: { editing = $0 }))
        .font(.system(size: 14).monospaced())
        .scrollContentBackground(.hidden)
        .padding(Spacing.s)
        .frame(minHeight: 320)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .cardShadow(RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
      HStack(spacing: Spacing.xs) {
        PageButton(title: .loci("loci.save")) { save(text) }
          .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .changesData()
        PageButton(title: .loci("dialog.cancel")) { editing = nil }
      }
    }
  }

  private func save(_ core: String) {
    Task {
      do throws(HostError) {
        _ = try await host.run(SaveSoul(core: core))
        editing = nil
      } catch {
        showFailure(error)
      }
    }
  }
}

/// The core of the Soul as the page sets it: serif paragraphs under small sans-serif headings.
private struct SoulCore: View {
  let markdown: String

  var body: some View {
    StructuredText(markdown, parser: SerifMarkdown(face: Serif.Face(size: 15.5)))
      .lineSpacing(15.5 * 0.8 - 4)
      .foregroundStyle(Palette.ink)
      .textual.headingStyle(SmallHeading())
      .textual.structuredTextStyle(.default)
      .textual.textSelection(.enabled)
  }
}

/// A heading in the Soul or a diary: small, sans-serif and muted, so the writing under it leads.
struct SmallHeading: StructuredText.HeadingStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .medium))
      .fontDesign(.default)
      .foregroundStyle(Palette.inkMuted)
      .textual.blockSpacing(.init(top: 20, bottom: 6))
  }
}

/// The traits Loci grew, newest first, on a thin line with a ring at each.
private struct TraitTimeline: View {
  let traits: [Line<Trait>]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      PageLabel(title: Text(.loci("loci.traits")), file: "\(traits.count) / \(Soul.traitLimit)")
      VStack(alignment: .leading, spacing: 14) {
        ForEach(traits.indices, id: \.self) { index in
          row(traits[index])
        }
      }
      .padding(.leading, 14)
      .overlay(alignment: .leading) { Rectangle().fill(Palette.lineStrong).frame(width: 1) }
    }
  }

  private func row(_ line: Line<Trait>) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      switch line {
      case .entry(let trait):
        if let day = trait.day {
          Text(verbatim: day.short).font(.system(size: 10.5).monospaced()).foregroundStyle(Palette.inkFaint)
        }
        Text(verbatim: trait.text)
      case .text(let text):
        Text(verbatim: text)
      }
    }
    .font(.system(size: 13.5))
    .lineSpacing(3)
    .foregroundStyle(Palette.ink)
    .overlay(alignment: .topLeading) {
      Circle()
        .strokeBorder(Palette.accent, lineWidth: 1.5)
        .background(Circle().fill(Palette.canvas))
        .frame(width: 8, height: 8)
        .offset(x: -18.5, y: 6)
    }
  }
}

/// Above a part of the page: what it is, and the file it is kept in.
struct PageLabel: View {
  let title: Text
  var file: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
      title.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.inkMuted)
      if let file { Text(verbatim: file).font(.system(size: 11).monospaced()).foregroundStyle(Palette.inkFaint) }
    }
  }
}

/// A small capsule button on a card's face.
struct PageButton: View {
  let title: LocalizedStringResource
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12.5))
        .foregroundStyle(Palette.ink)
        .padding(.vertical, 5)
        .padding(.horizontal, Spacing.s)
        .background(Palette.surface, in: Capsule())
        .cardShadow(Capsule())
    }
    .buttonStyle(PressStyle())
  }
}
