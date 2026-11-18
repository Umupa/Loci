import LociModel
import SwiftUI

extension JobLine.Activity {
  var name: LocalizedStringResource {
    switch self {
    case .fetching: .loci("job.fetching")
    case .downloading: .loci("job.downloading")
    case .recognizing: .loci("job.recognizing")
    case .translating: .loci("job.translating")
    case .outlining: .loci("job.outlining")
    case .queued: .loci("job.queued")
    }
  }
}

extension JobLine.Fix {
  /// The words on the button.
  @ViewBuilder var label: some View {
    switch self {
    case .downloadComponent: Text(.loci("job.downloadComponent"))
    case .downloadModel(let model):
      HStack(spacing: 0) {
        Text(.loci("job.downloadModel"))
        Text(verbatim: " · ")
        Text(verbatim: model.sizeText).font(Typography.mono).foregroundStyle(Palette.inkMuted)
      }
    case .signIn: Text(.loci("job.signIn"))
    case .chooseAgent: Text(.loci("job.chooseAgent"))
    case .update(let component): Text(joining: Text(.loci("job.update")), Text(verbatim: " " + component.name))
    case .chooseBrowserLogin: Text(.loci("job.chooseBrowserLogin"))
    case .retry: Text(.loci("job.retry"))
    case .resume: Text(.loci("job.resume"))
    }
  }

  /// What stopped the work, shown before the button; an outdated component is named rather than quoted.
  func why(_ reason: String?) -> Text? {
    switch self {
    case .update(let component): Text(joining: Text(verbatim: component.name + " "), Text(.loci("job.outdated")))
    case .signIn(let site): Text(joining: Text(.loci("job.needsLogin")), Text(verbatim: " " + site))
    default: reason.map { Text(verbatim: $0) }
    }
  }
}

extension Component {
  /// As the program calls itself.
  var name: String {
    switch self {
    case .ytDlp: "yt-dlp"
    case .ffmpeg: "FFmpeg"
    case .quickJS: "QuickJS"
    }
  }
}
