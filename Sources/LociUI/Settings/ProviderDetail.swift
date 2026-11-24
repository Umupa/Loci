import LociModel
import SwiftUI

/// A provider opened in place: its name and protocol when it is one of your own, its address, its key and its
/// models. Each field is saved when Return is pressed or the field is left.
struct ProviderDetail: View {
  let provider: ModelProvider
  let model: ModelServicesModel
  @State private var name = ""
  @State private var address = ""
  @State private var key = ""
  @State private var keyShown = false
  @State private var keyRead = false
  @State private var keyTicks = 0
  @FocusState private var focus: Field?

  enum Field: Hashable { case name, address, key }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if provider.preset == .custom {
        line(.loci("models.name")) {
          field(.name, text: $name, prompt: String(localized: .loci("models.custom")), monospaced: false)
        }
        line(.loci("models.protocol")) {
          PopupPicker(
            selection: api,
            options: [
              (ModelAPI.openAI, Text(.loci("models.compatible"))), (ModelAPI.anthropic, Text(verbatim: "Anthropic")),
            ])
          Spacer()
        }
      }
      line(.loci("models.address")) {
        field(.address, text: $address, prompt: "https://", invalid: !address.isEmpty && ModelAddress(address) == nil)
      }
      line(.loci("models.key")) { keyField }
      line(.loci("models.model")) {
        ModelChips(provider: provider, model: model)
      }
    }
    .padding(.leading, 52)
    .padding(.trailing, 12)
    .padding(.top, 2)
    .padding(.bottom, 14)
    .onAppear {
      name = provider.name
      address = provider.address?.url.absoluteString ?? ""
    }
    .onChange(of: focus) { left, _ in
      if let left { commit(left) }
    }
  }

  private var keyField: some View {
    HStack(spacing: 6) {
      Group {
        if keyShown {
          TextField(text: $key, prompt: Text(verbatim: model.hasKey(provider.id) ? "••••••••••••" : "")) {
            Text(.loci("models.key"))
          }
        } else {
          SecureField(text: $key, prompt: Text(verbatim: model.hasKey(provider.id) ? "••••••••••••" : "")) {
            Text(.loci("models.key"))
          }
        }
      }
      .textFieldStyle(.plain)
      .font(.system(size: 12.5).monospaced())
      .focused($focus, equals: .key)
      .onSubmit { commit(.key) }
      if model.hasKey(provider.id), key.isEmpty || keyRead {
        Image(systemName: Symbols.saved)
          .font(.system(size: 13))
          .foregroundStyle(Palette.ready)
          .symbolEffect(.bounce, value: keyTicks)
          .transition(.scale.combined(with: .opacity))
          .accessibilityLabel(Text(.loci("models.keySaved")))
      }
      Button {
        Task { await reveal() }
      } label: {
        Image(systemName: keyShown ? Symbols.conceal : Symbols.reveal)
          .font(.system(size: 12))
          .foregroundStyle(Palette.inkMuted)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(PressStyle())
      .help(Text(.loci(keyShown ? "models.hideKey" : "models.showKey")))
      .accessibilityLabel(Text(.loci(keyShown ? "models.hideKey" : "models.showKey")))
    }
    .modifier(FieldFace(focused: focus == .key, invalid: false))
    .animation(Motion.quick, value: model.hasKey(provider.id))
  }

  private func line<Content: View>(_ label: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(label)
        .font(.system(size: 12.5))
        .foregroundStyle(Palette.inkMuted)
        .frame(width: 52, height: 30, alignment: .leading)
      content()
    }
  }

  private func field(
    _ which: Field, text: Binding<String>, prompt: String, monospaced: Bool = true, invalid: Bool = false
  ) -> some View {
    TextField(text: text, prompt: Text(verbatim: prompt)) { Text(verbatim: prompt) }
      .textFieldStyle(.plain)
      .font(monospaced ? .system(size: 12.5).monospaced() : .system(size: 12.5))
      .focused($focus, equals: which)
      .onSubmit { commit(which) }
      .modifier(FieldFace(focused: focus == which, invalid: invalid))
  }

  private var api: Binding<ModelAPI> {
    Binding {
      provider.api
    } set: { api in
      model.change(provider.id) { $0.api = api }
    }
  }

  private func commit(_ which: Field) {
    switch which {
    case .name:
      let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
      model.change(provider.id) { $0.name = name }
    case .address:
      let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
      if text.isEmpty, provider.preset == .custom {
        model.change(provider.id) { $0.address = nil }
      } else if let valid = ModelAddress(text) {
        model.change(provider.id) { $0.address = valid }
      }
    case .key:
      let typed = key.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !typed.isEmpty || keyRead else { return }
      Task {
        guard await model.setKey(typed, for: provider.id) else { return }
        keyRead = !typed.isEmpty
        keyTicks += 1
        if typed.isEmpty { keyShown = false }
      }
    }
  }

  private func reveal() async {
    if keyShown {
      keyShown = false
      return
    }
    if key.isEmpty, model.hasKey(provider.id), let saved = await model.key(for: provider.id) {
      key = saved
      keyRead = true
    }
    keyShown = true
  }
}

/// A field's face on the page: a light well with a hairline, an amber ring while typing, a red one when what is
/// in it cannot be used.
struct FieldFace: ViewModifier {
  let focused: Bool
  let invalid: Bool
  private static let well = Color(dark: 0x26231F, light: 0xFFFFFF)

  func body(content: Content) -> some View {
    content
      .padding(.leading, 10)
      .padding(.trailing, 4)
      .frame(height: 30)
      .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Self.well))
      .overlay {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(
            invalid ? Palette.failure : focused ? Palette.accentLine : Palette.lineStrong,
            lineWidth: focused || invalid ? 1 : Size.hairline)
      }
      .animation(Motion.quick, value: focused)
  }
}
