import AppKit
import SwiftUI

/// What a snapshot draws in place of things that do not render off screen — a web page, a video's frames —
/// and the moment of a reader it opens on. The app never sets it.
struct StandIns {
  var webPage: NSImage?
  var moment: MediaMoment?
  /// The list of a page's videos is open.
  var videoPickerOpen = false
  /// The pointer rests on the sidebar's foot, or on the first Mac in settings' list.
  var pointerOnMachineFoot = false
  var pointerOnFirstPairedMac = false
  /// Words of the reading text selected, with the bar over them.
  var selection: String?
}

/// A reader of a video or audio item caught part way through.
struct MediaMoment {
  var playing = true
  /// Sentences chosen in the transcript, by index.
  var chosen: ClosedRange<Int>?
  /// The transcript was scrolled away from the sentence playing.
  var scrolledAway = false
  var subtitleMenuOpen = false
  var panel: MediaTab?
}

extension EnvironmentValues {
  @Entry var standIns: StandIns?
}
