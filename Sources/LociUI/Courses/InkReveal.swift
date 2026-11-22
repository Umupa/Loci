import SwiftUI

/// Words coming up in ink a character at a time: each one fades in out of a blur and settles a little.
/// `progress` runs from 0, nothing yet, to 1, every character down.
struct InkReveal: TextRenderer, Animatable {
  var progress: Double

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  nonisolated func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    let glyphs = layout.flatMap { $0 }.flatMap { $0 }
    let count = Double(max(glyphs.count, 1))
    let spread = 0.75
    for (index, glyph) in glyphs.enumerated() {
      let start = Double(index) / count * spread
      let shown = min(max((progress - start) / (1 - spread), 0), 1)
      guard shown > 0 else { continue }
      var ink = context
      if shown < 1 {
        ink.opacity = shown
        ink.addFilter(.blur(radius: 5 * (1 - shown)))
        ink.translateBy(x: 0, y: 2 * (1 - shown))
      }
      ink.draw(glyph)
    }
  }
}

/// `text` inked in once it first shows, or each time it changes; shown at once while the person has asked for
/// less motion. `held` catches it part way, for a snapshot.
struct InkedText: View {
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.standIns) private var standIns
  let text: Text
  let characters: Int
  var held: Double?
  /// Whether it comes up in ink; words already there when the page opens are simply there.
  var fresh = true
  @State private var progress = 0.0

  init(_ text: Text, characters: Int, held: Double? = nil, fresh: Bool = true) {
    self.text = text
    self.characters = characters
    self.held = held
    self.fresh = fresh
  }

  var body: some View {
    text
      .textRenderer(InkReveal(progress: held ?? progress))
      .onAppear(perform: ink)
  }

  private func ink() {
    guard fresh, !reduceMotion, standIns == nil else {
      progress = 1
      return
    }
    progress = 0
    withAnimation(.linear(duration: Double(characters) * Motion.inkPerCharacter + 0.4)) { progress = 1 }
  }
}

extension InkedText {
  /// `words` in the serif at `face`.
  init(serif words: String, _ face: Serif.Face, held: Double? = nil, fresh: Bool = true) {
    self.init(Text(serif: words, face), characters: words.count, held: held, fresh: fresh)
  }

  init(plain words: String, held: Double? = nil, fresh: Bool = true) {
    self.init(Text(verbatim: words), characters: words.count, held: held, fresh: fresh)
  }
}
