import LociModel
import SwiftUI

/// The import panel's steps on one line down their left: the video or audio, the site's subtitles,
/// recognition on this Mac, and translation. A step turned off folds away.
struct ImportSteps: View {
  @Environment(\.host) private var host
  @Binding var draft: ImportDraft
  /// `nil` for files on this Mac, which have no video step.
  let media: Media?
  let setup: MediaSetup?
  let offersSubtitles: Bool
  @State private var installations: [AgentInstallation] = []
  @State private var models: [String] = []

  struct Media: Equatable {
    let isAudio: Bool
    let sizes: [ImportChoice.Quality: Int64]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let media { keeping(media) }
      if offersSubtitles, media?.isAudio == false { subtitles }
      recognition
      translation
    }
    .background(alignment: .topLeading) {
      Rectangle().fill(Palette.lineStrong)
        .frame(width: 1.5)
        .padding(.leading, 15.25)
        .padding(.top, 22)
        .padding(.bottom, 26)
    }
    .animation(Motion.standard, value: draft)
    .task(id: draft.translating.runtime?.provider) { await readAgents() }
  }

  private func keeping(_ media: Media) -> some View {
    ImportStep(
      symbol: Symbols.download, title: media.isAudio ? .loci("import.audio") : .loci("import.video"), on: true
    ) {
      EmptyView()
    } content: {
      VStack(spacing: Spacing.xs) {
        HStack(spacing: Spacing.xs) {
          ChoiceCard(chosen: draft.keeping == .local, action: { draft.keeping = .local }) {
            Label {
              Text(.loci("import.keepLocal"))
            } icon: {
              Image(systemName: Symbols.disk)
            }
          }
          ChoiceCard(chosen: draft.keeping == .online, action: { draft.keeping = .online }) {
            Label {
              Text(.loci("import.watchOnline"))
            } icon: {
              Image(systemName: Symbols.online)
            }
          }
        }
        if draft.keeping == .local, !media.isAudio {
          HStack(spacing: Spacing.xs) {
            ForEach(ImportChoice.Quality.allCases, id: \.self) { quality in
              QualityCard(
                name: Self.name(of: quality), size: media.sizes[quality], chosen: draft.quality == quality
              ) {
                draft.quality = quality
              }
            }
          }
          .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
    }
  }

  private var subtitles: some View {
    ImportStep(symbol: Symbols.subtitles, title: .loci("import.siteSubtitles"), on: draft.subtitles) {
      if draft.offered.count > 1 {
        PopupPicker(
          selection: Binding(get: { draft.subtitleLanguage ?? "" }, set: { draft.subtitleLanguage = $0 }),
          options: draft.offered.map { ($0, Text(verbatim: Languages.name(of: $0))) })
      } else if let only = draft.offered.first {
        Text(verbatim: Languages.name(of: only)).font(.system(size: 12.5)).foregroundStyle(Palette.inkMuted)
      }
      StepSwitch(on: Binding(get: { draft.subtitles }, set: { draft.useSubtitles($0) }))
    } content: {
      EmptyView()
    }
  }

  private var recognition: some View {
    ImportStep(symbol: Symbols.recognizing, title: .loci("import.recognition"), on: draft.recognizes) {
      StepSwitch(on: Binding(get: { draft.recognizes }, set: { draft.recognize($0) }))
    } content: {
      SettingsWell {
        SettingRow(label: .loci("import.language")) {
          PopupPicker(
            selection: $draft.recognizing.language,
            options: [(String?.none, Text(.loci("import.detectLanguage")))]
              + Languages.spoken.map { (String?.some($0), Text(verbatim: Languages.name(of: $0))) })
        }
        SettingRow(label: .loci("import.model")) {
          PopupPicker(
            selection: $draft.recognizing.model,
            options: SpeechModel.allCases.map { ($0, modelTitle($0)) })
        }
      }
    }
  }

  private var translation: some View {
    ImportStep(symbol: Symbols.translate, title: .loci("import.translation"), on: draft.translates) {
      StepSwitch(on: $draft.translates)
    } content: {
      SettingsWell {
        SettingRow(label: .loci("import.translateInto")) {
          PopupPicker(
            selection: $draft.translating.language,
            options: Languages.targets(keeping: draft.translating.language).map {
              ($0, Text(verbatim: Languages.name(of: $0)))
            })
        }
        SettingRow(label: .loci("import.runtime")) {
          PopupPicker(
            selection: provider,
            options: [(Provider?.none, Text(.loci("import.followLoci")))]
              + Agents.choosable(installations, keeping: draft.translating.runtime?.provider ?? .codex).map {
                (Provider?.some($0), Text(verbatim: Agents.name(of: $0)))
              })
        }
        if let runtime = draft.translating.runtime {
          SettingRow(label: .loci("import.model")) {
            PopupPicker(
              selection: Binding(
                get: { runtime.model },
                set: {
                  draft.translating.runtime = Runtime(provider: runtime.provider, model: $0, effort: runtime.effort)
                }),
              options: [(String?.none, Text(.loci("agents.anyModel")))]
                + Agents.offered(models, keeping: runtime.model).map {
                  (String?.some($0), Text(verbatim: Agents.modelName($0)))
                })
            if !runtime.provider.efforts.isEmpty {
              PopupPicker(
                selection: Binding(
                  get: { runtime.effort },
                  set: {
                    draft.translating.runtime = Runtime(provider: runtime.provider, model: runtime.model, effort: $0)
                  }),
                options: [(ThinkingEffort?.none, Text(.loci("agents.anyModel")))]
                  + runtime.provider.efforts.map { (ThinkingEffort?.some($0), Text(Agents.effortName($0))) })
            }
          }
          .transition(.opacity)
        }
      }
    }
  }

  private var provider: Binding<Provider?> {
    Binding {
      draft.translating.runtime?.provider
    } set: { provider in
      draft.translating.runtime = provider.map { Runtime(provider: $0) }
    }
  }

  /// The model's name, with its size when it is not on this Mac yet.
  private func modelTitle(_ model: SpeechModel) -> Text {
    let ready = setup?.speechModels.first { $0.model == model }?.state == .ready
    return ready ? model.title : Text(joining: model.title, Text(verbatim: "  " + model.sizeText))
  }

  private func readAgents() async {
    installations = (try? await host.run(DetectAgents())) ?? []
    guard let provider = draft.translating.runtime?.provider else { return }
    models = (try? await host.run(AgentModels(provider: provider))) ?? []
  }

  static func name(of quality: ImportChoice.Quality) -> Text {
    switch quality {
    case .hd1080: Text(verbatim: "1080p")
    case .hd720: Text(verbatim: "720p")
    case .audio: Text(.loci("import.audioOnly"))
    }
  }
}
