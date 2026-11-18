import LociModel
import SwiftUI

/// The seven Whisper models: which one recognition uses, how fast and how accurate each is, its size, and
/// whether it is here.
struct SpeechModels: View {
  @Environment(\.host) private var host
  let setup: MediaSetup

  var body: some View {
    SettingsGroup(title: .loci("media.speech"), inset: 40) {
      VStack(spacing: 0) {
        header
        ForEach(Array(setup.speechModels.enumerated()), id: \.element.model) { index, status in
          if index > 0 {
            Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline).padding(.leading, 40)
          }
          row(status)
        }
      }
    }
  }

  private var header: some View {
    columns(
      Color.clear, Color.clear, Text(.loci("media.speed")), Text(.loci("media.accuracy")), Color.clear, Color.clear
    )
    .font(.system(size: 11, weight: .medium))
    .foregroundStyle(Palette.inkFaint)
    .padding(.top, Spacing.xs)
    .padding(.bottom, 2)
    .frame(minHeight: 30)
  }

  private func row(_ status: SpeechModelStatus) -> some View {
    let here = status.state == .ready
    let chosen = status.model == setup.speechModel
    return columns(
      Radio(on: chosen && here, enabled: here) { run(SetSpeechModel(status.model)) },
      HStack(spacing: Spacing.xs) {
        status.model.title.foregroundStyle(here ? Palette.ink : Palette.inkMuted)
        if status.model == .recommended {
          Text(.loci("media.recommended"))
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Palette.accentInk)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Palette.tint))
        }
      }
      .lineLimit(1),
      Dots(filled: status.model.speed), Dots(filled: status.model.accuracy),
      Text(verbatim: status.model.sizeText).font(Typography.mono).foregroundStyle(Palette.inkFaint)
        .frame(maxWidth: .infinity, alignment: .trailing),
      action(status)
    )
    .font(.system(size: 13))
    .padding(.vertical, 6)
    .frame(minHeight: 40)
  }

  @ViewBuilder private func action(_ status: SpeechModelStatus) -> some View {
    HStack(spacing: 6) {
      switch status.state {
      case .ready:
        Text(.loci("media.downloaded")).font(.system(size: 12)).foregroundStyle(Palette.inkFaint)
        Menu {
          Button(role: .destructive) {
            run(DeleteSpeechModel(status.model))
          } label: {
            Text(.loci("media.delete"))
          }
        } label: {
          Image(systemName: Symbols.more).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.inkMuted)
            .frame(width: 22, height: 22)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
      case .transferring(.running(let share)):
        Meter(share: share?.value ?? 0, width: 52)
        Text(verbatim: share.map { "\(Int(($0.value * 100).rounded()))%" } ?? "").font(Typography.mono)
          .foregroundStyle(Palette.inkMuted)
      case .transferring(.failed(let reason)):
        Button {
          run(DownloadSpeechModel(status.model))
        } label: {
          Text(.loci("job.retry"))
        }
        .buttonStyle(PushStyle())
        .help(Text(verbatim: reason))
      case .absent:
        Button {
          run(DownloadSpeechModel(status.model))
        } label: {
          Text(.loci("media.download"))
        }
        .buttonStyle(PushStyle())
      }
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
  }

  private func run<C: Command>(_ command: C) {
    Task { _ = try? await host.run(command) }
  }

  /// The table's columns: choice, name, speed, accuracy, size, what can be done.
  private func columns(
    _ radio: some View, _ name: some View, _ speed: some View, _ accuracy: some View, _ size: some View,
    _ action: some View
  ) -> some View {
    HStack(spacing: Spacing.s) {
      radio.frame(width: Size.radio)
      name.frame(maxWidth: .infinity, alignment: .leading)
      speed.frame(width: 52, alignment: .leading)
      accuracy.frame(width: 52, alignment: .leading)
      size.frame(width: 70)
      action.frame(width: 104)
    }
    .padding(.horizontal, 12)
  }
}

/// Five dots, the first few filled: a model's speed or accuracy.
private struct Dots: View {
  let filled: Int

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<5, id: \.self) { index in
        Circle()
          .fill(index < filled ? Palette.inkMuted : Palette.fillStrong)
          .overlay(Circle().strokeBorder(index < filled ? .clear : Palette.line, lineWidth: Size.hairline))
          .frame(width: Size.dot, height: Size.dot)
      }
    }
  }
}

/// A radio button in amber when on; faded while what it chooses is not here yet.
private struct Radio: View {
  let on: Bool
  let enabled: Bool
  let choose: () -> Void

  var body: some View {
    Button(action: choose) {
      ZStack {
        if on {
          Circle().fill(Palette.accent)
          Circle().fill(.white).frame(width: 6, height: 6)
        } else {
          Circle().fill(Palette.thumb)
          Circle().strokeBorder(Palette.lineStrong, lineWidth: 1)
        }
      }
      .frame(width: Size.radio, height: Size.radio)
      .shadow(color: .black.opacity(0.06), radius: 0.5, y: 0.5)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .opacity(enabled || on ? 1 : 0.45)
  }
}
