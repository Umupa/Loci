import LociModel
import SwiftUI

/// What the dot by the companion's face says: awake, or away.
enum PresenceTone: Equatable {
  case awake, away

  /// Green while awake or a little tired; gray while sleepy or asleep, and while the Mac it lives on is
  /// offline. A Mac that does not say how tired it is counts as awake.
  init(tiredness: Tiredness?, offline: Bool) {
    switch (offline, tiredness) {
    case (true, _), (false, .sleepy?), (false, .asleep?): self = .away
    case (false, .awake?), (false, .tired?), (false, nil): self = .awake
    }
  }

  var color: Color { self == .awake ? Palette.presenceAwake : Palette.presenceAway }
}

/// The dot in the corner of the companion's face, ringed in what it sits on so it stands off the face.
struct PresenceDot: View {
  let tone: PresenceTone
  let size: CGFloat
  var ring: Color = Palette.canvas

  var body: some View {
    Circle()
      .fill(tone.color)
      .frame(width: size, height: size)
      .padding(size * 0.22)
      .background(ring, in: Circle())
      .animation(.easeInOut(duration: 0.3), value: tone)
      .accessibilityHidden(true)
  }
}

extension View {
  /// Puts the dot in the bottom-right corner of a face `side` points wide.
  func presenceDot(_ tone: PresenceTone, side: CGFloat, ring: Color = Palette.canvas) -> some View {
    let dot = max(7, side * 0.15)
    return overlay(alignment: .bottomTrailing) {
      PresenceDot(tone: tone, size: dot, ring: ring).offset(x: dot * 0.2, y: dot * 0.2)
    }
  }
}

/// How the companion is now, for the dot and the line under its name, read once for the window.
struct CompanionNow: Equatable {
  var presence: LociPresence?
  var work: LociWork?
  var offline: Bool

  var tone: PresenceTone { PresenceTone(tiredness: presence?.tiredness, offline: offline) }
}

extension EnvironmentValues {
  @Entry var companionNow = CompanionNow(presence: nil, work: nil, offline: false)
}
