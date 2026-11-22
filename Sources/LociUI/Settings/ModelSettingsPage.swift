import LociModel
import SwiftUI

struct ModelSettingsPage: View {
  static let symbol = "cpu"
  @Environment(\.host) private var host
  @State private var equipment: Feed<MediaSetup>?
  @State private var runtime: Feed<Runtime>?
  @State private var access: (any ModelSettingsAccess)?
  @State private var saved: ModelSettingsState?
  @State private var draft = ServiceDraft()
  @State private var translation = TranslationSettings()
  @State private var busy = false
  @State private var testing = false
  @State private var connected: Bool?
  @State private var failure: LocalizedStringResource?

  var body: some View {
    SettingsPage(symbol: Self.symbol, title: .loci("settings.models")) {
      serviceGroup
      piComponent
      translationGroup
      SettingsGroup(title: nil) {
        SettingsRow {
          Text(.loci("models.cache"))
        } trailing: {
          Text(verbatim: cacheSize).foregroundStyle(Palette.inkMuted).monospacedDigit()
          Button {
            clearCache()
          } label: {
            Text(.loci("models.clearCache"))
          }
          .buttonStyle(PushStyle())
          .disabled((saved?.cacheBytes ?? 0) == 0)
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    .disabled(saved == nil || busy)
    .changesData()
    .onChange(of: draft) {
      connected = nil
      failure = nil
    }
    .subscribing(MediaSettings(), into: $equipment)
    .subscribing(CurrentRuntime(), into: $runtime)
    .task { await load() }
  }

  @ViewBuilder private var piComponent: some View {
    if let setup = equipment?.value, let status = setup.components.first(where: { $0.component == .bundledPi }) {
      let work = setup.componentWork.first { $0.component == .bundledPi }?.state
      if runtime?.value?.provider == .bundledPi || work != nil {
        SettingsGroup(title: nil, inset: 50) {
          ComponentRow(status: status, work: work, install: piInstallAction)
        }
      }
    }
  }

  private var piInstallAction: (() -> Void)? {
    guard saved?.hasKey == true else { return nil }
    return { installPi() }
  }

  private func installPi() {
    Task { _ = try? await host.run(InstallComponent(.bundledPi)) }
  }

  private var footer: some View {
    HStack {
      if let failure {
        Text(failure).font(.system(size: 12)).foregroundStyle(Palette.inkMuted)
      }
      Spacer()
      Button {
        save()
      } label: {
        Text(.loci("models.save"))
      }
      .buttonStyle(PushStyle())
      .disabled(!canSave)
    }
    .padding(.horizontal, Spacing.xl)
    .padding(.vertical, 10)
    .frame(maxWidth: Size.settingsWidth)
    .frame(maxWidth: .infinity)
    .background(Palette.canvas)
    .overlay(alignment: .top) {
      Rectangle().fill(Palette.line).frame(height: Size.hairline)
    }
  }

  private var serviceGroup: some View {
    SettingsGroup(title: nil) {
      SettingsRow {
        Text(.loci("models.provider"))
      } trailing: {
        PopupPicker(
          selection: $draft.provider,
          options: ModelServiceProvider.allCases.map { ($0, Text($0.name)) })
      }
      if draft.provider == .compatible {
        field(.loci("models.address"), value: $draft.address, hint: "https://example.com/v1")
      }
      field(.loci("models.model"), value: $draft.model)
      SettingsRow {
        Text(.loci("models.key"))
      } trailing: {
        SecureField(
          "", text: $draft.key, prompt: Text(hasStoredKey ? .loci("models.keySaved") : .loci("models.key"))
        )
        .accessibilityLabel(Text(.loci("models.key")))
        .frame(width: 180)
        if hasStoredKey {
          Button {
            removeKey()
          } label: {
            Text(.loci("models.removeKey"))
          }
          .buttonStyle(PushStyle())
        }
      }
      SettingsRow {
        if let connected {
          Label {
            Text(connected ? .loci("models.connected") : .loci("models.connectionFailed"))
          } icon: {
            Image(systemName: connected ? "checkmark.circle" : "exclamationmark.circle")
          }
          .foregroundStyle(Palette.inkMuted)
        }
      } trailing: {
        if testing { ProgressView().controlSize(.small) }
        Button {
          test()
        } label: {
          Text(.loci("models.test"))
        }
        .buttonStyle(PushStyle())
        .disabled(testing || draft.service == nil)
      }
    }
  }

  private var translationGroup: some View {
    SettingsGroup(title: .loci("models.translation")) {
      SettingsRow {
        Text(.loci("models.targetLanguage"))
      } trailing: {
        PopupPicker(
          selection: $translation.language,
          options: [(String?.none, Text(.loci("language.system")))]
            + Languages.targets.map {
              (String?.some($0), Text(verbatim: Languages.name(of: $0)))
            })
      }
      SettingsRow {
        Text(.loci("models.smart"))
      } trailing: {
        Toggle(isOn: $translation.smart) { Text(.loci("models.smart")) }
          .labelsHidden().toggleStyle(.switch).controlSize(.small)
      }
      prompt(
        .loci("models.transcriptPrompt"), value: $translation.transcriptPrompt,
        original: TranslationSettings.defaultTranscriptPrompt)
      prompt(
        .loci("models.articlePrompt"), value: $translation.articlePrompt,
        original: TranslationSettings.defaultArticlePrompt)
    }
  }

  private func field(_ label: LocalizedStringResource, value: Binding<String>, hint: String = "") -> some View {
    SettingsRow {
      Text(label)
    } trailing: {
      TextField(text: value, prompt: Text(verbatim: hint)) { Text(label) }
        .labelsHidden().frame(width: 240)
    }
  }

  private func prompt(_ label: LocalizedStringResource, value: Binding<String>, original: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(label)
        Spacer()
        Button {
          value.wrappedValue = original
        } label: {
          Text(.loci("models.restorePrompt"))
        }
        .buttonStyle(PushStyle())
        .disabled(value.wrappedValue == original)
      }
      TextEditor(text: value)
        .accessibilityLabel(Text(label))
        .font(.system(size: 12))
        .scrollContentBackground(.hidden)
        .frame(height: 64)
        .padding(4)
        .background(Palette.canvas, in: .rect(cornerRadius: 5))
        .overlay {
          RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.line, lineWidth: Size.hairline)
        }
    }
    .font(.system(size: 13))
    .foregroundStyle(Palette.ink)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private var hasStoredKey: Bool {
    guard let saved, let service = saved.settings.service else { return false }
    return saved.hasKey && draft.service?.endpoint == service.endpoint && draft.provider == service.provider
  }

  private var canSave: Bool {
    guard let saved else { return false }
    let changed =
      translation != saved.settings.translation || draft.service != saved.settings.service || !draft.key.isEmpty
    let valid = draft.service != nil || (draft.model.isEmpty && draft.key.isEmpty)
    return changed && valid && !testing
  }

  private var cacheSize: String {
    guard let saved else { return "—" }
    return ByteCountFormatter.string(fromByteCount: saved.cacheBytes, countStyle: .file)
  }

  private func load() async {
    access = await host.modelSettingsAccess()
    do throws(HostError) {
      guard let access else { return }
      let state = try await access.readModelSettings()
      apply(state)
    } catch {
      failure = Messages.describe(error)
    }
  }

  private func apply(_ state: ModelSettingsState) {
    saved = state
    translation = state.settings.translation
    if let service = state.settings.service {
      draft.provider = service.provider
      draft.model = service.model
      draft.address = service.provider == .compatible ? service.baseURL.absoluteString : ""
    }
    draft.key = ""
  }

  private func save() {
    guard let access else { return }
    let settings = ModelSettings(service: draft.service, translation: translation)
    let key: ModelKeyChange = draft.key.isEmpty ? .keep : .replace(draft.key)
    change { () async throws(HostError) in
      apply(try await access.saveModelSettings(settings, key: key))
    }
  }

  private func removeKey() {
    guard let access, let settings = saved?.settings else { return }
    change { () async throws(HostError) in
      saved = try await access.saveModelSettings(settings, key: .remove)
      connected = nil
    }
  }

  private func clearCache() {
    guard let access else { return }
    change { () async throws(HostError) in
      try await access.clearTranslationCache()
      saved = try await access.readModelSettings()
    }
  }

  private func change(_ action: @escaping @MainActor () async throws(HostError) -> Void) {
    busy = true
    failure = nil
    Task {
      defer { busy = false }
      do throws(HostError) {
        try await action()
      } catch {
        failure = Messages.describe(error)
      }
    }
  }

  private func test() {
    guard let access, let service = draft.service else { return }
    let key = draft.key
    let input = draft
    connected = nil
    failure = nil
    testing = true
    Task {
      defer { testing = false }
      do throws(HostError) {
        try await access.testModelService(service, key: key.isEmpty ? nil : key)
        if input == draft { connected = true }
      } catch {
        if input == draft {
          connected = false
          if case .invalidRequest(let reason) = error { failure = .loci("models.connectionReason \(reason)") }
        }
      }
    }
  }
}

private struct ServiceDraft: Equatable {
  var provider: ModelServiceProvider = .openAI
  var address = ""
  var model = ""
  var key = ""

  var service: ModelService? {
    ModelService(provider: provider, model: model, baseURL: URL(string: address.trimmingCharacters(in: .whitespaces)))
  }
}

extension ModelServiceProvider {
  fileprivate var name: LocalizedStringResource {
    switch self {
    case .openAI: "OpenAI"
    case .anthropic: "Anthropic"
    case .openRouter: "OpenRouter"
    case .deepSeek: "DeepSeek"
    case .compatible: .loci("models.compatible")
    }
  }
}
