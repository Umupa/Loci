import LociModel
import SwiftUI

/// Settings › Model Services: the providers, one line each, opened in place; the tool model; and how translations
/// are asked for and with which model. Everything is saved as it is changed.
struct ModelServicesPage: View {
  @Environment(\.host) private var host
  @State private var model: ModelServicesModel?
  @State private var open: ModelProviderID?
  @State private var offUnfolded: Bool
  @State private var adding = false

  /// `open` and `offUnfolded` give how the page first shows, for pictures of it.
  init(open: ModelProviderID? = nil, offUnfolded: Bool = false) {
    _open = State(initialValue: open)
    _offUnfolded = State(initialValue: offUnfolded)
  }

  var body: some View {
    SettingsPage(symbol: Symbols.models, title: .loci("settings.models")) {
      if let model, model.state != nil {
        providers(model)
        toolModel(model)
        TranslationGroup(model: model)
      } else if let failure = model?.failure {
        Text(failure).font(.system(size: 12)).foregroundStyle(Palette.inkMuted)
      } else {
        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
      }
    }
    .changesData()
    .sheet(isPresented: $adding) {
      if let model {
        AddProviderSheet(added: Set(model.settings.providers.map(\.preset))) { preset in
          let added = model.add(preset)
          withAnimation(Motion.standard) { open = added }
        }
      }
    }
    .task {
      guard model == nil, let access = await host.modelSettingsAccess() else { return }
      let loading = ModelServicesModel(access: access)
      await loading.load()
      model = loading
    }
  }

  private func providers(_ model: ModelServicesModel) -> some View {
    let on = model.settings.providers.filter(\.enabled)
    let off = model.settings.providers.filter { !$0.enabled }
    return SettingsGroup(title: nil) {
      ForEach(on) { provider in
        ProviderRow(provider: provider, model: model, open: $open)
      }
      if !off.isEmpty {
        ProvidersOff(providers: off, unfolded: $offUnfolded)
        if offUnfolded {
          ForEach(off) { provider in
            ProviderRow(provider: provider, model: model, open: $open)
          }
        }
      }
      AddProviderRow { adding = true }
    }
    .animation(Motion.standard, value: model.settings.providers.map(\.enabled))
  }

  private func toolModel(_ model: ModelServicesModel) -> some View {
    SettingsGroup(title: nil) {
      SettingsRow {
        Text(.loci("models.toolModel"))
      } trailing: {
        ModelChoiceMenu(
          groups: model.groups,
          selection: Binding {
            model.settings.toolModel
          } set: { choice in
            model.change { $0.toolModel = choice }
          })
      }
    }
  }
}

/// How translations are asked for: with which model, into which language, with the whole text as context or not,
/// the prompts for transcripts and articles, and the translations kept so far.
private struct TranslationGroup: View {
  let model: ModelServicesModel
  @State private var transcriptPrompt = ""
  @State private var articlePrompt = ""

  var body: some View {
    SettingsGroup(title: .loci("models.translation")) {
      SettingsRow {
        Text(.loci("models.translationModel"))
      } trailing: {
        ModelChoiceMenu(
          groups: model.groups,
          selection: Binding {
            model.settings.translation.model
          } set: { choice in
            model.change { $0.translation.model = choice }
          }, following: .loci("models.followToolModel"))
      }
      SettingsRow {
        Text(.loci("models.targetLanguage"))
      } trailing: {
        PopupPicker(
          selection: Binding {
            model.settings.translation.language
          } set: { language in
            model.change { $0.translation.language = language }
          },
          options: [(String?.none, Text(.loci("language.system")))]
            + Languages.targets.map { (String?.some($0), Text(verbatim: Languages.name(of: $0))) })
      }
      SettingsRow {
        Text(.loci("models.smart"))
      } trailing: {
        Toggle(
          isOn: Binding {
            model.settings.translation.smart
          } set: { smart in
            model.change { $0.translation.smart = smart }
          }
        ) {
          Text(.loci("models.smart"))
        }
        .labelsHidden()
        .toggleStyle(AmberSwitch(small: true))
      }
      PromptEditor(
        label: .loci("models.transcriptPrompt"), text: $transcriptPrompt,
        original: TranslationSettings.defaultTranscriptPrompt
      ) { prompt in
        model.change { $0.translation.transcriptPrompt = prompt }
      }
      PromptEditor(
        label: .loci("models.articlePrompt"), text: $articlePrompt, original: TranslationSettings.defaultArticlePrompt
      ) { prompt in
        model.change { $0.translation.articlePrompt = prompt }
      }
      SettingsRow {
        Text(.loci("models.cache"))
      } trailing: {
        Text(verbatim: ByteCountFormatter.string(fromByteCount: model.state?.cacheBytes ?? 0, countStyle: .file))
          .foregroundStyle(Palette.inkMuted)
          .monospacedDigit()
        IconButton(symbol: "trash", title: .loci("models.clearCache"), size: 26, symbolSize: 12.5) {
          Task { await model.clearCache() }
        }
        .disabled((model.state?.cacheBytes ?? 0) == 0)
      }
    }
    .onAppear {
      transcriptPrompt = model.settings.translation.transcriptPrompt
      articlePrompt = model.settings.translation.articlePrompt
    }
  }
}

/// A prompt to edit, saved when it is left, with an icon to put the default back.
private struct PromptEditor: View {
  let label: LocalizedStringResource
  @Binding var text: String
  let original: String
  let save: (String) -> Void
  @FocusState private var editing: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Text(label)
        Spacer()
        IconButton(symbol: Symbols.undo, title: .loci("models.restorePrompt"), size: 26, symbolSize: 12.5) {
          text = original
          save(original)
        }
        .disabled(text == original)
      }
      TextEditor(text: $text)
        .accessibilityLabel(Text(label))
        .font(.system(size: 12))
        .scrollContentBackground(.hidden)
        .focused($editing)
        .frame(height: 64)
        .padding(4)
        .background(Palette.canvas, in: .rect(cornerRadius: 7))
        .overlay {
          RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
        }
        .onChange(of: editing) { _, now in
          if !now { save(text) }
        }
    }
    .font(.system(size: 13))
    .foregroundStyle(Palette.ink)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }
}
