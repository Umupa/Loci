import LociModel
import SwiftUI

/// What floats over a book's pages: going back from a followed link, the table of contents and the reading
/// settings at the top, and the bar across the whole book at the foot.
struct BookChrome: View {
  let reader: BookReader
  @Binding var size: Int
  @Binding var spacing: BookSettings.Spacing
  @Binding var face: BookSettings.Face
  @State private var showingContents = false
  @State private var showingSettings = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: Spacing.xxs) {
        Spacer()
        if reader.back != nil {
          Button {
            Task { await reader.goBack() }
          } label: {
            Label {
              Text(.loci("book.back"))
            } icon: {
              Image(systemName: Symbols.followedBack)
            }
            .font(Typography.body)
          }
          .buttonStyle(QuietButtonStyle())
          .transition(.opacity)
        }
        IconButton(symbol: Symbols.contents, title: .loci("book.contents")) { showingContents.toggle() }
          .popover(isPresented: $showingContents, arrowEdge: .bottom) {
            BookContentsList(reader: reader) { showingContents = false }
          }
        IconButton(symbol: Symbols.textSize, title: .loci("book.settings"), glyphLocale: Symbols.latinGlyphs) {
          showingSettings.toggle()
        }
        .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
          BookSettingsForm(size: $size, spacing: $spacing, face: $face)
        }
      }
      .padding(.horizontal, Spacing.m)
      .frame(height: BookLayout.top)
      Spacer()
      BookProgressBar(reader: reader)
        .padding(.horizontal, reader.layout.margin)
        .frame(height: BookLayout.top)
    }
    .animation(Motion.quick, value: reader.back)
  }
}

/// The book's own table of contents, its levels indented, the entry being read marked.
struct BookContentsList: View {
  let reader: BookReader
  let chose: () -> Void

  var body: some View {
    let current = reader.contents.toc.lastIndex { $0.chapter <= reader.chapter }
    ScrollViewReader { scroller in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array(reader.contents.toc.enumerated()), id: \.offset) { index, entry in
            Button {
              chose()
              Task { await reader.show(entry) }
            } label: {
              Text(verbatim: entry.title)
                .font(entry.depth == 0 ? Typography.bodyEmphasis : Typography.body)
                .foregroundStyle(index == current ? Palette.ink : Palette.inkMuted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, CGFloat(entry.depth) * Spacing.m)
                .padding(.vertical, 7)
                .padding(.horizontal, Spacing.s)
                .background(
                  RoundedRectangle(cornerRadius: Radius.row).fill(index == current ? Palette.fillStrong : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .id(index)
          }
        }
        .padding(Spacing.xs)
      }
      .onAppear { if let current { scroller.scrollTo(current, anchor: .center) } }
    }
    .frame(width: 300, height: 420)
  }
}

/// Size, line spacing and face, for every book.
struct BookSettingsForm: View {
  @Binding var size: Int
  @Binding var spacing: BookSettings.Spacing
  @Binding var face: BookSettings.Face

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      HStack(spacing: Spacing.s) {
        IconButton(symbol: Symbols.textSmaller, title: .loci("book.smaller"), glyphLocale: Symbols.latinGlyphs) {
          size = max(BookSettings.sizes.lowerBound, size - 1)
        }
        .disabled(size <= BookSettings.sizes.lowerBound)
        Text(verbatim: "\(size)")
          .font(Typography.body.monospacedDigit())
          .foregroundStyle(Palette.ink)
          .frame(maxWidth: .infinity)
        IconButton(symbol: Symbols.textLarger, title: .loci("book.larger"), glyphLocale: Symbols.latinGlyphs) {
          size = min(BookSettings.sizes.upperBound, size + 1)
        }
        .disabled(size >= BookSettings.sizes.upperBound)
      }
      Picker(selection: $spacing) {
        ForEach(BookSettings.Spacing.allCases, id: \.self) { Text($0.name).tag($0) }
      } label: {
        EmptyView()
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      Picker(selection: $face) {
        ForEach(BookSettings.Face.allCases, id: \.self) { Text($0.name).tag($0) }
      } label: {
        EmptyView()
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
    .padding(Spacing.m)
    .frame(width: 240)
  }
}

/// A line across the whole book, filled as far as the page; dragging it shows which chapter is under the finger
/// and letting go jumps there.
struct BookProgressBar: View {
  let reader: BookReader
  @State private var dragging: Double?
  @State private var hovering = false

  var body: some View {
    GeometryReader { frame in
      let share = dragging ?? reader.share.value
      let x = frame.size.width * share
      ZStack(alignment: .leading) {
        Capsule().fill(Palette.fillStrong).frame(height: 3)
        Capsule().fill(Palette.inkMuted).frame(width: max(3, x), height: 3)
        Circle()
          .fill(Palette.ink)
          .frame(width: 11, height: 11)
          .offset(x: x - 5.5)
          .opacity(hovering || dragging != nil ? 1 : 0)
        if let dragging, let title = title(at: dragging) {
          Text(verbatim: title)
            .font(Typography.body)
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 5)
            .background(Capsule().fill(Palette.floating))
            .overlay(Capsule().strokeBorder(Palette.line))
            .fixedSize()
            .position(x: min(max(x, 80), frame.size.width - 80), y: frame.size.height / 2 - 24)
        }
      }
      .frame(maxHeight: .infinity)
      .contentShape(Rectangle())
      .onHover { hovering = $0 }
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { dragging = min(max($0.location.x / max(frame.size.width, 1), 0), 1) }
          .onEnded { _ in
            guard let dragging else { return }
            self.dragging = nil
            Task { await reader.show(share: Fraction(dragging)) }
          })
    }
    .accessibilityElement()
    .accessibilityLabel(Text(.loci("book.progress")))
    .accessibilityValue(Text(reader.share.value, format: .percent.precision(.fractionLength(0))))
  }

  private func title(at share: Double) -> String? {
    reader.contents.place(of: Fraction(share)).flatMap { reader.contents.entry(for: $0.chapter)?.title }
  }
}
