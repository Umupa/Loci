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
  func showingDocuments(opened: (id: AnyHashable, document: LociDocument)? = nil) -> some View {
    modifier(DocumentStage(shown: opened))
  }
}

private struct DocumentStage: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var space
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
      .overlay {
        if let shown {
          DocumentSheet(document: shown.document, id: shown.id, space: space) {
            withAnimation(reduceMotion ? nil : Self.close) {
              self.shown = nil
            } completion: {
              hidden = nil
            }
          }
        }
      }
  }

  private static let open = Animation.spring(duration: 0.52, bounce: 0.18)
  private static let close = Animation.spring(duration: 0.38, bounce: 0)
}

/// A document opened over the conversation, which blurs behind it: collapse at the top left, more at the
/// top right. Escape collapses it too.
private struct DocumentSheet: View {
  @Environment(\.host) private var host
  let document: LociDocument
  let id: AnyHashable
  let space: Namespace.ID
  let close: () -> Void
  @State private var saved = false

  /// Over the blurred conversation: deep in dark, a wash of paper in light.
  private static let veil = Color(nsColor: NSColor(dark: 0x0A0908, light: 0xFCFBF8, alpha: (dark: 0.62, light: 0.45)))

  var body: some View {
    ZStack(alignment: .top) {
      Rectangle()
        .fill(.regularMaterial)
        .overlay(Self.veil)
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        .transition(.opacity)
      page
        .padding(.top, 80)
        .transition(.opacity)
      HStack {
        circle(Symbols.collapse, label: .loci("document.collapse"), action: close)
          .keyboardShortcut(.cancelAction)
        Spacer()
        Menu {
          Button(.loci("conversation.copy")) { CopyButton.put(document.markdown) }
          Button(saved ? .loci("document.saved") : .loci("document.save")) { save() }
            .disabled(saved)
            .changesData()
        } label: {
          Image(systemName: Symbols.more).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.ink)
            .frame(width: 44, height: 44)
            .glassEffect(.regular, in: .circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(.loci("document.more")))
      }
      .padding(18)
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
      .padding(.top, 44)
      .padding(.bottom, 60)
    }
    .scrollIndicators(.never)
    .frame(maxWidth: 680, maxHeight: .infinity)
    .background(Palette.surface)
    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
    .shadow(color: .black.opacity(0.25), radius: 40, y: 30)
    .matchedGeometryEffect(id: id, in: space)
  }

  private func circle(_ symbol: String, label: LocalizedStringResource, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.ink)
        .frame(width: 44, height: 44)
        .contentShape(.circle)
        .glassEffect(.regular, in: .circle)
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel(Text(label))
  }

  /// Puts the document in the library as an article Loci wrote.
  private func save() {
    let title = document.title ?? String(document.body.prefix(40))
    Task {
      let added = try? await host.run(
        AddTextItem(fileName: title + ".md", text: document.markdown, title: title, authors: [LociAuthor.name]))
      if added != nil { saved = true }
    }
  }
}
