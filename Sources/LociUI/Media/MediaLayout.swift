import SwiftUI

/// Where the panel goes: beside the stage when the window has room for both, otherwise folded away and opened
/// over the stage on request.
struct MediaLayout: Equatable {
  let width: CGFloat
  let panelShown: Bool
  let panelOver: Bool

  /// The stage is never narrower than this while the panel is beside it.
  static let stageMinimum: CGFloat = 480

  var roomy: Bool { width >= Size.mediaPanel + Self.stageMinimum }
  var besideStage: Bool { panelShown && roomy }
  var overStage: Bool { panelOver && !roomy }
}
