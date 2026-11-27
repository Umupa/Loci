import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// UI-S8, UI-S30: what the companion runs on, in the 模型 tab and beside the send button.
@MainActor
@Suite(.serialized, .onStage)
struct RuntimeSnapshots {
  private static func sample() throws -> Sample {
    var sample = try Sample(problems: false)
    sample.ownRuntimes = [
      .init(
        conversation: .item(sample.borg.id), title: sample.borg.title,
        runtime: Runtime(provider: .antigravity, model: "gemini-4-hydrogen", effort: .high)),
      .init(conversation: .project(EntityID()), title: "Loci", runtime: Runtime(provider: .grok, model: "grok-5")),
    ]
    return sample
  }

  /// UI-S30: a row for each kind, with the agent and model, how hard it thinks, and the conversations that chose
  /// their own under their kind.
  @Test(arguments: Snapshot.Appearance.allCases)
  func modelsTab(appearance: Snapshot.Appearance) async throws {
    let view = HStack(spacing: 0) { LociScreen(tab: .models) }
      .lociHost(FakeHost(try Self.sample(), library: try SampleLibrary()))
    try await ScreenSnapshots.shoot("loci-models", view, appearance: appearance, size: CGSize(width: 1036, height: 820))
    try await ScreenSnapshots.shoot(
      "loci-models-en", view, appearance: appearance, english: true, size: CGSize(width: 1036, height: 820))
  }

  /// UI-S8: the capsule says what this conversation runs on; the picker under it chooses the agent, the model and
  /// the thinking, and offers going back to the kind's default or making this the default.
  @Test(arguments: Snapshot.Appearance.allCases)
  func capsuleAndPicker(appearance: Snapshot.Appearance) async throws {
    let sample = try Self.sample()
    let own = Runtime(provider: .codex, model: "gpt-6.1-sol", effort: .high)
    let view = VStack(alignment: .trailing, spacing: 18) {
      RuntimePicker(runtime: own, installations: FakeHost.installations, change: { _ in }) {
        VStack(spacing: 6) {
          Hairline().padding(.top, 6)
          HStack {
            RuntimeLabel(
              runtime: Runtime(provider: .claudeCode, model: "opus", effort: .medium), showsEffort: true, muted: true
            )
            .padding(.horizontal, 8)
            Spacer()
            Button(.loci("runtime.makeDefault")) {}.buttonStyle(AmberButtonStyle())
          }
        }
      }
      .background(RoundedRectangle(cornerRadius: 14).fill(Palette.menuFace))
      .cardShadow(RoundedRectangle(cornerRadius: 14))
      HStack(spacing: 0) {
        RuntimeCapsule(conversation: .item(sample.borg.id))
        AttachButton {}
      }
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.canvas)
    .lociHost(FakeHost(sample))
    try await ScreenSnapshots.shoot(
      "runtime-picker", view, appearance: appearance, size: CGSize(width: 460, height: 560))
  }
}
