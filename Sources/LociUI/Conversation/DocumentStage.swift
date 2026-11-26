import LociModel
import SwiftUI

/// Where document cards open: the conversation they sit in, which the open document covers.
struct Documents {
  let space: Namespace.ID
  /// The card whose document is open.
  let shown: AnyHashable?
  /// The card hidden while its document is open or still closing back into it.
  let hidden: AnyHashable?
  let open: (AnyHashable, LociDocument) -> Void
}

extension EnvironmentValues {
  @Entry var documents: Documents?
}

extension View {
  /// Lets the document cards inside open their documents over this view; `opened` starts with one open.
  func showingDocuments(
    opened: (id: AnyHashable, document: LociDocument)? = nil, coversPanels: Bool = false
  ) -> some View {
    modifier(DocumentStage(coversPanels: coversPanels, shown: opened))
  }
}

private struct DocumentStage: ViewModifier {
  @Environment(\.reducesMotion) private var reduceMotion
  @Namespace private var space
  let coversPanels: Bool
  @State var shown: (id: AnyHashable, document: LociDocument)?
  @State private var hidden: AnyHashable?

  func body(content: Content) -> some View {
    content
      .environment(
        \.documents,
        Documents(space: space, shown: shown?.id, hidden: hidden ?? shown?.id) { id, document in
          hidden = id
          withAnimation(reduceMotion ? nil : Self.open) { shown = (id, document) }
        }
      )
      .allowsHitTesting(shown == nil)
      .accessibilityHidden(shown != nil)
      .overlay {
        if let shown {
          DocumentSheet(document: shown.document, id: shown.id, space: space, coversPanels: coversPanels) {
            withAnimation(reduceMotion ? nil : Self.close) {
              self.shown = nil
            } completion: {
              if self.shown == nil { hidden = nil }
            }
          }
        }
      }
  }

  private static let open = Animation.spring(duration: 0.52, bounce: 0.18)
  private static let close = Animation.spring(duration: 0.38, bounce: 0)
}

/// A document opened over the conversation, which blurs behind it. Its tools sit on the paper's top edge and stay
/// there while it scrolls: collapse on the left; copy and save to the library on the right. Escape collapses it too.
private struct DocumentSheet: View {
  let document: LociDocument
  let id: AnyHashable
  let space: Namespace.ID
  let coversPanels: Bool
  let close: () -> Void

  /// Over the blurred conversation: deep in dark, a wash of paper in light.
  private static let veil = Color(nsColor: NSColor(dark: 0x0A0908, light: 0xFCFBF8, alpha: (dark: 0.62, light: 0.45)))

  private var paperWidth: CGFloat { coversPanels ? 720 : 680 }
  private var shape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
  }

  var body: some View {
    ZStack(alignment: .top) {
      Group {
        if coversPanels {
          Palette.canvas
        } else {
          Rectangle().fill(.regularMaterial).overlay(Self.veil)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture(perform: close)
      .transition(.opacity)
      page
        .padding(.top, 28)
        .transition(.opacity)
    }
  }

  private var page: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        if let title = document.title {
          Text(Serif.attributed(title, Serif.Face(size: 34, weight: .semibold))).foregroundStyle(Palette.ink)
            .textSelection(.enabled)
        }
        RichText(markdown: document.body, font: .system(size: 15.5), tables: .headerRule)
      }
      .padding(.horizontal, 40)
      .padding(.top, Self.toolsHeight + 12)
      .padding(.bottom, 60)
    }
    .overlay(alignment: .top) { tools }
    .frame(maxWidth: paperWidth, maxHeight: .infinity)
    .background(Palette.surface)
    .clipShape(shape)
    .overlay(shape.strokeBorder(Palette.line, lineWidth: Size.hairline).allowsHitTesting(false))
    .shadow(
      color: coversPanels ? Palette.liftShadow.opacity(0.48) : .black.opacity(0.25),
      radius: coversPanels ? 32 : 40, y: coversPanels ? 18 : 30
    )
    .matchedGeometryEffect(id: id, in: space)
    .padding(.horizontal, Spacing.m)
  }

  private var tools: some View {
    HStack(spacing: Spacing.xxs) {
      DocumentTool(symbol: Symbols.unfold, label: .loci("document.collapse"), action: close)
        .keyboardShortcut(.cancelAction)
      Spacer()
      DocumentCopy(markdown: document.markdown)
      DocumentSave(document: document)
    }
    .padding(.horizontal, 14)
    .frame(height: Self.toolsHeight)
    .background(Palette.surface)
  }

  private static let toolsHeight: CGFloat = 56
}

/// One of the round tools on a document's top edge.
private struct DocumentTool: View {
  let symbol: String
  let label: LocalizedStringResource
  var tint = Palette.ink
  var help: LocalizedStringResource?
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(tint)
        .contentTransition(.symbolEffect(.replace))
        .frame(width: 34, height: 34)
        .background(Circle().fill(hovering ? Palette.fillStrong : Palette.fill))
        .contentShape(.circle)
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
    .help(Text(help ?? label))
    .accessibilityLabel(Text(label))
  }
}

/// Copies the document's Markdown; a tick stands in for a moment once it is on the pasteboard.
private struct DocumentCopy: View {
  let markdown: String
  @State private var copied = false

  var body: some View {
    DocumentTool(
      symbol: copied ? Symbols.done : Symbols.copy,
      label: copied ? .loci("conversation.copied") : .loci("conversation.copy"),
      tint: copied ? Palette.accentInk : Palette.ink
    ) {
      CopyButton.put(markdown)
      withAnimation(Motion.quick) { copied = true }
      Task {
        try? await Task.sleep(for: .seconds(1.5))
        withAnimation(Motion.quick) { copied = false }
      }
    }
  }
}

/// Puts the document in the library as an article Loci wrote. The button says how it went where it is: filled
/// once saved, a mark with the reason when it was not, and clicking that tries again.
private struct DocumentSave: View {
  @Environment(\.host) private var host
  let document: LociDocument
  @State private var state = DocumentSaving.idle

  var body: some View {
    Group {
      switch state {
      case .idle:
        DocumentTool(symbol: Symbols.library, label: .loci("document.save"), action: save)
      case .saving:
        ProgressView().controlSize(.small).frame(width: 34, height: 34)
      case .saved:
        DocumentTool(symbol: Symbols.libraryKept, label: .loci("document.saved"), tint: Palette.accent) {}
          .disabled(true)
      case .failed(let error):
        DocumentTool(
          symbol: Symbols.retry, label: .loci("document.save"), tint: Palette.accent,
          help: Messages.describe(error), action: save)
      }
    }
    .changesData()
  }

  private func save() {
    let title = document.title ?? String(document.body.prefix(40))
    withAnimation(Motion.quick) { state = .saving }
    Task {
      do throws(HostError) {
        _ = try await host.run(
          AddTextItem(fileName: title + ".md", text: document.markdown, title: title, authors: [Item.companionCredit]))
        withAnimation(Motion.quick) { state = .saved }
      } catch {
        withAnimation(Motion.quick) { state = .failed(error) }
      }
    }
  }
}

private enum DocumentSaving {
  case idle, saving, saved
  case failed(HostError)
}
