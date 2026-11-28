import LociModel
import SwiftUI

/// Picks a model: a rail of favorites and agents beside the chosen tab's models, searchable, each one starrable.
struct ModelFlyout: View {
  let runtime: Runtime
  let installations: [AgentInstallation]
  var width: CGFloat = 314
  let select: (Runtime) -> Void
  var favorites: ModelFavorites = .shared
  @State private var tab: FlyoutTab
  @State private var query = ""
  @State private var models: Feed<[AgentModel]>?
  @State private var cachedModels: [Provider: [AgentModel]] = [:]
  @State private var modelOptions: Feed<ModelOptions>?

  init(
    runtime: Runtime, installations: [AgentInstallation], width: CGFloat = 314,
    favorites: ModelFavorites = .shared, select: @escaping (Runtime) -> Void
  ) {
    self.runtime = runtime
    self.installations = installations
    self.width = width
    self.favorites = favorites
    self.select = select
    _tab = State(initialValue: .provider(runtime.provider))
  }

  private var choosable: [Provider] {
    Agents.choosable(installations, keeping: runtime.provider)
  }

  private var activeProvider: Provider? {
    if case .provider(let provider) = tab { provider } else { nil }
  }

  private var normalizedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  var body: some View {
    HStack(spacing: 0) {
      rail
      Rectangle().fill(Palette.lineStrong).frame(width: Size.hairline)
      mainPane
    }
    .frame(width: width, height: 252)
    .subscribing(activeProvider.map(AgentModelList.init), into: $models)
    .subscribing(AvailableModels(), into: $modelOptions)
    .onChange(of: models?.value) {
      guard let activeProvider, let loaded = models?.value else { return }
      cachedModels[activeProvider] = loaded
    }
  }

  private var rail: some View {
    ScrollView(.vertical) {
      VStack(spacing: 3) {
        RailButton(selected: tab == .favorites, isStar: true, label: Text(.loci("models.favorites"))) {
          tab = .favorites
        } icon: {
          Image(systemName: tab == .favorites ? Symbols.starFilled : Symbols.star)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(tab == .favorites ? Palette.accent : Palette.inkMuted)
        }
        ForEach(choosable, id: \.self) { provider in
          let selected = tab == .provider(provider)
          RailButton(selected: selected, label: Text(Agents.label(of: provider))) {
            tab = .provider(provider)
          } icon: {
            AgentMark(provider: provider, size: 17, plain: true)
              .saturation(selected ? 1 : 0)
              .opacity(selected ? 1 : 0.52)
          }
        }
      }
      .padding(5)
    }
    .scrollIndicators(.never)
    .frame(width: 44)
  }

  private var mainPane: some View {
    VStack(spacing: 0) {
      searchBar
      Rectangle().fill(Palette.line).frame(height: Size.hairline)
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          switch tab {
          case .favorites:
            favoritesList
          case .provider(let provider):
            providerList(provider)
          }
        }
        .padding(4)
      }
      .scrollIndicators(.never)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var searchBar: some View {
    HStack(spacing: 7) {
      Image(systemName: Symbols.search).font(.system(size: 12)).foregroundStyle(Palette.inkMuted)
      TextField(
        "", text: $query, prompt: Text(.loci("models.search")).foregroundStyle(Palette.inkFaint)
      )
      .textFieldStyle(.plain)
      .font(.system(size: 13))
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: Symbols.cancel).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.inkMuted)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private var favoritesList: some View {
    let entries = filteredFavorites
    if entries.isEmpty {
      VStack(spacing: 6) {
        Image(systemName: Symbols.star).font(.system(size: 16)).foregroundStyle(Palette.inkFaint)
        Text(.loci("models.none")).font(.system(size: 12)).foregroundStyle(Palette.inkFaint)
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 76)
    } else {
      ForEach(entries, id: \.self) { entry in
        modelRow(
          provider: entry.provider, id: entry.id, display: currentName(of: entry),
          providerBadge: Agents.name(of: entry.provider), showMark: true)
      }
    }
  }

  @ViewBuilder
  private func providerList(_ provider: Provider) -> some View {
    let listed = provider == activeProvider ? (models?.value ?? cachedModels[provider]) : cachedModels[provider]
    let offered = Agents.offered(listed ?? [], keeping: provider == runtime.provider ? runtime.model : nil)
    let filtered =
      normalizedQuery.isEmpty
      ? offered
      : offered.filter {
        $0.name.lowercased().contains(normalizedQuery) || $0.id.lowercased().contains(normalizedQuery)
      }

    if normalizedQuery.isEmpty, provider != .bundledPi {
      autoRow(for: provider)
    }

    if provider == .bundledPi, let groups = modelOptions?.value?.groups, !groups.isEmpty, normalizedQuery.isEmpty {
      bundledPiGroupedList(offered: filtered, groups: groups)
    } else {
      ForEach(filtered, id: \.id) { model in
        modelRow(provider: provider, id: model.id, display: model.name, providerBadge: nil, showMark: false)
      }
    }

    if listed == nil {
      ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 10)
    }
  }

  @ViewBuilder
  private func bundledPiGroupedList(offered: [AgentModel], groups: [ModelGroup]) -> some View {
    let byID = Dictionary(uniqueKeysWithValues: offered.map { ($0.id, $0) })
    let groupedIDs = Set(groups.flatMap { $0.choices().map(\.runtimeModel) })
    let ungrouped = offered.filter { !groupedIDs.contains($0.id) }
    ForEach(groups, id: \.provider) { group in
      let items = group.choices().compactMap { byID[$0.runtimeModel] }
      if !items.isEmpty {
        ModelWords.name(of: group)
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(Palette.inkFaint)
          .padding(.horizontal, 8)
          .padding(.top, 6)
          .padding(.bottom, 2)
        ForEach(items, id: \.id) { model in
          modelRow(provider: .bundledPi, id: model.id, display: model.name, providerBadge: nil, showMark: false)
        }
      }
    }
    ForEach(ungrouped, id: \.id) { model in
      modelRow(provider: .bundledPi, id: model.id, display: model.name, providerBadge: nil, showMark: false)
    }
  }

  private func autoRow(for provider: Provider) -> some View {
    let chosen = provider == runtime.provider && runtime.model == nil
    return FlyoutRow(chosen: chosen) {
      select(Runtime(provider: provider, effort: runtime.effort))
    } label: {
      Text(.loci("agents.anyModel"))
        .font(.system(size: 13, weight: chosen ? .semibold : .regular))
        .foregroundStyle(Palette.inkMuted)
      Spacer(minLength: 0)
    } trailing: {
      if chosen { checkmark }
    }
  }

  private func modelRow(
    provider: Provider, id: String, display: String, providerBadge: String?, showMark: Bool
  ) -> some View {
    let chosen = provider == runtime.provider && id == runtime.model
    let favorited = favorites.contains(provider: provider, model: id)
    let split = Agents.splitModelTag(display)

    return FlyoutRow(chosen: chosen, alwaysShowAccessory: favorited) {
      select(Runtime(provider: provider, model: id, effort: runtime.effort))
    } label: {
      if showMark {
        AgentMark(provider: provider, size: 14, plain: true)
      }
      HStack(spacing: 5) {
        Text(verbatim: split.title)
          .font(.system(size: 13, weight: chosen ? .semibold : .regular))
          .foregroundStyle(Palette.ink)
          .lineLimit(1)
        if let tag = split.tag {
          Text(verbatim: tag).font(.system(size: 11)).foregroundStyle(Palette.inkMuted).lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      if let providerBadge {
        Text(verbatim: providerBadge).font(.system(size: 10.5)).foregroundStyle(Palette.inkFaint).lineLimit(1)
      }
    } accessory: { hovered in
      Button {
        favorites.toggle(provider: provider, model: id, name: display)
      } label: {
        Image(systemName: favorited ? Symbols.starFilled : Symbols.star)
          .font(.system(size: 11))
          .foregroundStyle(favorited ? Palette.accent : Palette.inkFaint)
          .frame(width: 22, height: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .opacity(favorited || hovered ? 1 : 0)
      .help(Text(.loci(favorited ? "models.favoriteRemove" : "models.favoriteAdd")))
    } trailing: {
      if chosen { checkmark }
    }
  }

  private var filteredFavorites: [FavoriteModel] {
    let allowed = Set(choosable)
    return favorites.items.filter { entry in
      guard allowed.contains(entry.provider) else { return false }
      guard !normalizedQuery.isEmpty else { return true }
      return entry.name.lowercased().contains(normalizedQuery)
        || entry.id.lowercased().contains(normalizedQuery)
        || Agents.name(of: entry.provider).lowercased().contains(normalizedQuery)
    }
  }

  private func currentName(of favorite: FavoriteModel) -> String {
    cachedModels[favorite.provider]?.first { $0.id == favorite.id }?.name ?? favorite.name
  }

  private var checkmark: some View {
    Image(systemName: Symbols.done).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.inkMuted)
  }
}

private enum FlyoutTab: Hashable {
  case favorites
  case provider(Provider)
}

private struct RailButton<Icon: View>: View {
  let selected: Bool
  var isStar = false
  let label: Text
  let activate: () -> Void
  @ViewBuilder let icon: () -> Icon
  @State private var hovering = false
  @State private var dwell: Task<Void, Never>?

  var body: some View {
    Button(action: activate) {
      icon()
        .opacity(selected || !hovering ? 1 : 0.9)
        .frame(width: 32, height: 32)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(selected ? Palette.selection : hovering ? Palette.fillStrong : .clear)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { over in
      hovering = over
      dwell?.cancel()
      guard over, !selected else { return }
      dwell = Task {
        try? await Task.sleep(for: Motion.railDwell)
        if !Task.isCancelled { activate() }
      }
    }
    .onDisappear { dwell?.cancel() }
    .help(label)
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

private struct FlyoutRow<Label: View, Accessory: View, Trailing: View>: View {
  let chosen: Bool
  var alwaysShowAccessory = false
  let action: () -> Void
  @ViewBuilder let label: () -> Label
  @ViewBuilder let accessory: (Bool) -> Accessory
  @ViewBuilder let trailing: () -> Trailing
  @State private var hovering = false

  init(
    chosen: Bool, alwaysShowAccessory: Bool = false, action: @escaping () -> Void,
    @ViewBuilder label: @escaping () -> Label,
    @ViewBuilder accessory: @escaping (Bool) -> Accessory = { _ in EmptyView() },
    @ViewBuilder trailing: @escaping () -> Trailing
  ) {
    self.chosen = chosen
    self.alwaysShowAccessory = alwaysShowAccessory
    self.action = action
    self.label = label
    self.accessory = accessory
    self.trailing = trailing
  }

  var body: some View {
    HStack(spacing: 4) {
      Button(action: action) {
        HStack(spacing: 7) {
          label()
        }
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      accessory(hovering)
      trailing().frame(width: 18)
    }
    .padding(.horizontal, 4)
    .frame(height: 31)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(hovering ? Palette.selection : chosen ? Palette.fill : .clear)
    )
    .onHover { hovering = $0 }
  }
}
