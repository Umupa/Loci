import AppKit
import LociModel
import SwiftUI

/// This Mac's invite link, to copy into Loci on another Mac. A ring drains as the link's time runs out, and a
/// fresh link takes its place when it does.
struct InviteSheet: View {
  @Environment(\.standIns) private var standIns
  let machines: any Machines
  let go: (RemoteSheetState?) -> Void
  @State private var invite: Invite?
  @State private var issued = Date.now
  @State private var copied = false

  var body: some View {
    Group {
      SheetTitle(text: Text(.loci("remote.invite")))
      HStack(spacing: 10) {
        TimelineView(.periodic(from: .now, by: standIns == nil ? 1 : 3600)) { context in
          TimeLeftRing(left: left(at: context.date))
        }
        Text(verbatim: invite?.link ?? "")
          .font(.system(size: 12.5).monospaced())
          .foregroundStyle(Palette.ink)
          .lineLimit(1)
          .truncationMode(.tail)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button(action: copy) {
          HStack(spacing: 6) {
            if copied { Image(systemName: Symbols.done).font(.system(size: 10, weight: .bold)) }
            Text(copied ? .loci("conversation.copied") : .loci("conversation.copy"))
          }
          .foregroundStyle(copied ? Palette.inkMuted : Palette.ink)
        }
        .buttonStyle(PushStyle())
        .disabled(invite == nil)
      }
      .padding(.leading, Spacing.s)
      .padding(.trailing, 6)
      .frame(height: 40)
      .background(RoundedRectangle(cornerRadius: Radius.group, style: .continuous).fill(Palette.surface))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.group, style: .continuous).strokeBorder(
          Palette.lineStrong, lineWidth: Size.hairline)
      }
      HStack {
        Spacer(minLength: 0)
        Button {
          go(nil)
        } label: {
          Text(.loci("remote.done"))
        }
        .buttonStyle(AmberButtonStyle())
      }
    }
    .remoteSheet(close: { go(nil) })
    .task {
      while !Task.isCancelled {
        do throws(PairingFailure) {
          let next = try await machines.invite()
          invite = next
          issued = .now
          copied = false
          try? await Task.sleep(for: .seconds(next.expires.date.timeIntervalSinceNow))
        } catch {
          go(.ended(error))
          return
        }
      }
    }
  }

  /// How much of the link's time is left, from 1 when it was made to 0 when it expires.
  private func left(at now: Date) -> Double {
    guard let invite else { return 1 }
    let whole = invite.expires.date.timeIntervalSince(issued)
    guard whole > 0 else { return 0 }
    return min(max(invite.expires.date.timeIntervalSince(now) / whole, 0), 1)
  }

  private func copy() {
    guard let invite else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(invite.link, forType: .string)
    copied = true
  }
}

/// A thin ring, full when there is all the time in the world and empty when there is none.
private struct TimeLeftRing: View {
  let left: Double

  var body: some View {
    ZStack {
      Circle().stroke(Palette.lineStrong, lineWidth: 1.6)
      Circle()
        .trim(from: 0, to: left)
        .stroke(Palette.inkFaint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .frame(width: 12, height: 12)
    .frame(width: Spacing.m, height: Spacing.m)
    .accessibilityHidden(true)
  }
}
