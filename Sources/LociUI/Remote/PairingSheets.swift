import LociModel
import SwiftUI

/// The four digits both Macs show, large enough to compare across a desk.
struct PairingCodeText: View {
  let code: PairingCode?

  var body: some View {
    Text(verbatim: code?.digits ?? "0000")
      .font(.system(size: Size.pairingCode, weight: .semibold).monospaced())
      .tracking(Size.pairingCode * 0.28)
      .padding(.leading, Size.pairingCode * 0.28)
      .foregroundStyle(Palette.ink)
      .opacity(code == nil ? 0 : 1)
      .padding(.top, Spacing.xxs)
      .padding(.bottom, 6)
  }
}

/// On the Mac being asked: which Mac wants to connect, the code, and the answer.
struct ApproveSheet: View {
  let request: PairingRequest
  let answer: (Bool) -> Void

  var body: some View {
    Group {
      MachineGlyph(model: request.from.model, size: Size.machineGlyph * 0.82, weight: .thin)
        .frame(width: Size.machineGlyph, height: Size.machineGlyph)
      SheetTitle(text: Text(.loci("remote.wantsToConnect \(request.from.name)")))
      PairingCodeText(code: request.code)
      HStack(spacing: Spacing.xs) {
        Button {
          answer(false)
        } label: {
          Text(.loci("remote.decline"))
        }
        .buttonStyle(SheetButtonStyle(fills: true))
        Button {
          answer(true)
        } label: {
          Text(.loci("remote.allow"))
        }
        .buttonStyle(SheetButtonStyle(prominent: true, fills: true))
      }
    }
    .remoteSheet(centered: true, close: { answer(false) })
  }
}

/// On the Mac asking: the other Mac, the code once the two have shaken hands, and waiting for its answer.
/// Closing the sheet drops the pairing on both Macs.
struct WaitSheet: View {
  let mac: NearbyMac
  let machines: any Machines
  let go: (RemoteSheetState?) -> Void
  @State private var code: PairingCode?

  var body: some View {
    Group {
      MachineGlyph(model: mac.model, size: Size.machineGlyph * 0.82, weight: .thin)
        .frame(width: Size.machineGlyph, height: Size.machineGlyph)
      SheetTitle(text: Text(verbatim: mac.name))
      PairingCodeText(code: code)
      HStack(spacing: Spacing.xs) {
        Spinner()
        Spacer(minLength: 0)
        Button {
          go(nil)
        } label: {
          Text(.loci("dialog.cancel"))
        }
        .buttonStyle(SheetButtonStyle())
      }
    }
    .remoteSheet(centered: true, close: { go(nil) })
    .task {
      for await step in machines.pair(with: mac) {
        switch step {
        case .code(let shown): code = shown
        case .paired: go(nil)
        case .failed(let failure): go(.ended(failure))
        }
      }
    }
  }
}
