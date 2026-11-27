import LociModel
import SwiftUI

/// What a choice of runtime is for: one conversation, or every conversation of a kind that did not choose its own.
enum RuntimeTarget {
  case conversation(ConversationRef)
  case kind(ConversationKind)
}

/// Chooses what a conversation, or with `kind` every conversation of a kind, runs on. The bundled Pi, before it is
/// ready, opens the model services when none offers a model yet, else the agents' settings, where it downloads.
@MainActor
func chooseRuntime(
  _ runtime: Runtime, for target: RuntimeTarget, on host: any LociModel.Host, openPlace: OpenPlace
) async {
  let set: Runtime?
  switch target {
  case .conversation(let conversation): set = try? await host.run(SetConversationRuntime(runtime, for: conversation))
  case .kind(let kind): set = try? await host.run(SetDefaultRuntime(runtime, for: kind))
  }
  guard set != nil, runtime.provider == .bundledPi, let access = await host.modelSettingsAccess() else { return }
  let installations = (try? await host.run(DetectAgents())) ?? []
  guard !Agents.bundledPiIsReady(installations) else { return }
  let state = try? await access.readModelSettings()
  let offered = state.map { state in state.settings.groups.contains { state.keys.contains($0.provider) } } ?? false
  openPlace(.settings(offered ? .agents : .models))
}

/// A round glyph in the field at the foot of a conversation, washed on hover.
struct RoundGlyphStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    GlyphBody(configuration: configuration)
  }

  private struct GlyphBody: View {
    let configuration: Configuration
    @State private var hovering = false

    var body: some View {
      configuration.label
        .frame(width: Size.composerButton, height: Size.composerButton)
        .background(Circle().fill(hovering ? Palette.fill : .clear))
        .contentShape(Circle())
        .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
        .onHover { hovering = $0 }
    }
  }
}
