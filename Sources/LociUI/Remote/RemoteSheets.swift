import LociModel
import SwiftUI

/// The sheet the window shows for pairing, one at a time.
enum RemoteSheetState: Hashable {
  /// Looking for Macs nearby.
  case adding
  case pairing(NearbyMac)
  case inviting
  /// A pasted invite link being used to pair with the Mac that made it.
  case joining(Invite)
  case failed(PairingFailure)

  /// Where a pairing that did not happen leaves the window: telling why, or closed when it was given up here.
  static func ended(_ failure: PairingFailure) -> RemoteSheetState? {
    failure == .cancelled ? nil : .failed(failure)
  }
}

/// Shows `sheet`; `go` moves to another sheet, or closes with `nil`.
struct RemoteSheets: View {
  let sheet: RemoteSheetState
  let machines: any Machines
  let go: (RemoteSheetState?) -> Void

  var body: some View {
    switch sheet {
    case .adding: AddMacSheet(machines: machines, go: go)
    case .pairing(let mac): WaitSheet(mac: mac, machines: machines, go: go)
    case .inviting: InviteSheet(machines: machines, go: go)
    case .joining(let invite): JoiningSheet(invite: invite, machines: machines, go: go)
    case .failed(let failure): FailedSheet(failure: failure) { go(nil) }
    }
  }
}

/// The Macs nearby, found while the sheet is open, and ways to create or join an invite link.
struct AddMacSheet: View {
  let machines: any Machines
  let go: (RemoteSheetState?) -> Void
  @State private var nearby: [NearbyMac] = []
  @State private var inviteText: String
  @State private var inviteError: InviteJoinError?
  @State private var connectTask: Task<Void, Never>?

  init(
    machines: any Machines, go: @escaping (RemoteSheetState?) -> Void,
    inviteText: String = "", inviteError: InviteJoinError? = nil
  ) {
    self.machines = machines
    self.go = go
    _inviteText = State(initialValue: inviteText)
    _inviteError = State(initialValue: inviteError)
  }

  var body: some View {
    Group {
      SheetTitle(text: Text(.loci("remote.addMacTitle")))
      if machines.availability == .available {
        availableBody
      } else {
        unavailableBody
      }
    }
    .remoteSheet(close: close)
    .onDisappear { connectTask?.cancel() }
    .task {
      guard machines.availability == .available else { return }
      for await found in machines.nearby() { nearby = found }
    }
  }

  @ViewBuilder private var availableBody: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      inviteField
      if let inviteError {
        HStack(spacing: 6) {
          Image(systemName: Symbols.problem).font(.system(size: 11.5)).accessibilityHidden(true)
          Text(inviteError.message).font(.system(size: 12.5))
        }
        .foregroundStyle(Palette.failure)
        .padding(.horizontal, 4)
      }
    }
    nearbyList
    HStack(spacing: Spacing.xs) {
      Button {
        cancelConnect()
        go(.inviting)
      } label: {
        Text(.loci("remote.createInvite"))
      }
      .buttonStyle(QuietButtonStyle())
      Spacer(minLength: 0)
      Button(action: close) {
        Text(.loci("dialog.cancel"))
      }
      .buttonStyle(QuietButtonStyle())
    }
  }

  private var inviteField: some View {
    let trimmed = inviteText.trimmingCharacters(in: .whitespacesAndNewlines)
    let validLink = Invite(pasted: trimmed) != nil
    let connecting = connectTask != nil
    return HStack(spacing: Spacing.xs) {
      Image(systemName: Symbols.link)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(validLink ? Palette.accent : Palette.inkFaint)
        .accessibilityHidden(true)
      TextField(
        text: $inviteText,
        prompt: Text(.loci("remote.invitePlaceholder")).foregroundStyle(Palette.inkFaint)
      ) {
        Text(.loci("remote.invitePlaceholder"))
      }
      .textFieldStyle(.plain)
      .font(.system(size: 13))
      .foregroundStyle(Palette.ink)
      .disabled(connecting)
      .onSubmit(connect)
      .onChange(of: inviteText) { _, _ in inviteError = nil }
      Button(action: connect) {
        HStack(spacing: 6) {
          if connecting { Spinner() }
          Text(connecting ? .loci("remote.connecting") : .loci("remote.connect"))
        }
      }
      .buttonStyle(AmberButtonStyle())
      .disabled(trimmed.isEmpty || connecting)
    }
    .padding(.leading, Spacing.s)
    .padding(.trailing, 5)
    .frame(height: 40)
    .background(RoundedRectangle(cornerRadius: Radius.group, style: .continuous).fill(Palette.surface))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.group, style: .continuous).strokeBorder(
        inviteError == nil ? Palette.lineStrong : Palette.failure, lineWidth: Size.hairline)
    }
  }

  private var nearbyList: some View {
    VStack(spacing: 0) {
      ForEach(Array(nearby.enumerated()), id: \.element.id) { index, mac in
        NearbyRow(mac: mac, ruled: index > 0) {
          cancelConnect()
          go(.pairing(mac))
        }
      }
      Spinner()
        .frame(maxWidth: .infinity)
        .frame(height: Size.settingsRow)
        .overlay(alignment: .top) {
          if !nearby.isEmpty {
            Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline).padding(.leading, 46)
          }
        }
    }
    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.surface))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(
        Palette.line, lineWidth: Size.hairline)
    }
    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
  }

  @ViewBuilder private var unavailableBody: some View {
    HStack(alignment: .top, spacing: Spacing.s) {
      Image(systemName: Symbols.problem)
        .font(.system(size: 15))
        .foregroundStyle(Palette.inkMuted)
        .padding(.top, 1)
        .accessibilityHidden(true)
      Text(machines.availability == .missingRelay ? .loci("remote.missingRelay") : .loci("remote.unavailable"))
        .font(Typography.body)
        .foregroundStyle(Palette.ink)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.m)
    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.surface))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(
        Palette.line, lineWidth: Size.hairline)
    }
    HStack {
      Spacer(minLength: 0)
      Button(action: close) {
        Text(.loci("dialog.ok"))
      }
      .buttonStyle(AmberButtonStyle())
    }
  }

  private func connect() {
    let text = inviteText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, connectTask == nil else { return }
    guard let invite = Invite(pasted: text) else {
      inviteError = .invalidFormat
      return
    }
    inviteError = nil
    connectTask = Task {
      defer { connectTask = nil }
      do throws(PairingFailure) {
        _ = try await machines.accept(invite)
        if !Task.isCancelled { go(nil) }
      } catch {
        if !Task.isCancelled { inviteError = .failure(error) }
      }
    }
  }

  private func cancelConnect() {
    connectTask?.cancel()
    connectTask = nil
  }

  private func close() {
    cancelConnect()
    go(nil)
  }
}

/// Inline validation or pairing failure shown in `AddMacSheet`.
enum InviteJoinError: Hashable {
  case invalidFormat
  case failure(PairingFailure)

  var message: LocalizedStringResource {
    switch self {
    case .invalidFormat: .loci("remote.inviteInvalid")
    case .failure(let failure): failure.message
    }
  }
}

private struct NearbyRow: View {
  let mac: NearbyMac
  let ruled: Bool
  let choose: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: choose) {
      HStack(spacing: 10) {
        MachineGlyph(model: mac.model, size: 17).frame(width: 20)
        Text(verbatim: mac.name).font(Typography.body).foregroundStyle(Palette.ink)
        Spacer(minLength: 0)
        Image(systemName: Symbols.forward)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(Palette.inkFaint)
          .opacity(hovering ? 1 : 0)
      }
      .padding(.leading, Spacing.s)
      .padding(.trailing, 14)
      .frame(height: Size.settingsRow)
      .background(hovering ? Palette.fill : .clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .overlay(alignment: .top) {
      if ruled { Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline).padding(.leading, 46) }
    }
  }
}

/// A Mac's kind as its symbol, in the quiet ink of things that are not text.
struct MachineGlyph: View {
  let model: MachineModel
  let size: CGFloat
  var weight = Font.Weight.regular

  var body: some View {
    Image(systemName: Symbols.machine(model))
      .font(.system(size: size, weight: weight))
      .foregroundStyle(Palette.inkMuted)
      .accessibilityHidden(true)
  }
}

/// While a pasted invite link pairs this Mac with the one that made it.
/// Closing the sheet cancels the pairing: the task asking the other Mac is dropped with it.
struct JoiningSheet: View {
  let invite: Invite
  let machines: any Machines
  let go: (RemoteSheetState?) -> Void

  var body: some View {
    Group {
      MachineGlyph(model: invite.from.model, size: Size.machineGlyph * 0.82, weight: .thin)
        .frame(width: Size.machineGlyph, height: Size.machineGlyph)
      SheetTitle(text: Text(verbatim: invite.from.name))
      HStack(spacing: Spacing.xs) {
        Spinner()
        Spacer(minLength: 0)
        Button {
          go(nil)
        } label: {
          Text(.loci("dialog.cancel"))
        }
        .buttonStyle(QuietButtonStyle())
      }
    }
    .remoteSheet(centered: true, close: { go(nil) })
    .task {
      do throws(PairingFailure) {
        _ = try await machines.accept(invite)
        if !Task.isCancelled { go(nil) }
      } catch {
        if !Task.isCancelled { go(.ended(error)) }
      }
    }
  }
}

/// Why a pairing did not happen.
struct FailedSheet: View {
  let failure: PairingFailure
  let close: () -> Void

  var body: some View {
    Group {
      SheetTitle(text: Text(failure.message))
      Button(action: close) {
        Text(.loci("dialog.ok"))
      }
      .buttonStyle(AmberButtonStyle())
    }
    .remoteSheet(centered: true, close: close)
  }
}

extension PairingFailure {
  var message: LocalizedStringResource {
    switch self {
    case .expired: .loci("remote.inviteExpired")
    case .used: .loci("remote.inviteUsed")
    case .selfInvite: .loci("remote.inviteSelf")
    case .declined: .loci("remote.declined")
    case .unreachable, .cancelled: .loci("remote.unreachable")
    }
  }
}
