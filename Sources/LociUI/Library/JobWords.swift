import LociModel
import SwiftUI

extension JobLine.Activity {
  var name: LocalizedStringResource {
    switch self {
    case .fetching: .loci("job.fetching")
    case .fetchingPage: .loci("stage.fetchPage")
    case .extracting: .loci("stage.extract")
    case .findingCover: .loci("stage.findCover")
    case .downloading: .loci("job.downloading")
    case .recognizing: .loci("job.recognizing")
    case .separatingSpeakers: .loci("job.separatingSpeakers")
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
    case .openSource: Text(.loci("job.openSource"))
    case .retry: Text(.loci("job.retry"))
    case .resume: Text(.loci("job.resume"))
    }
  }

  /// What stopped the work in a few words, shown before the button; an outdated component is named.
  func why(_ problem: JobLine.Problem?) -> Text? {
    switch self {
    case .update(let component): Text(joining: Text(verbatim: component.name + " "), Text(.loci("job.outdated")))
    case .signIn(let site): Text(joining: Text(.loci("job.needsLogin")), Text(verbatim: " " + site))
    default: problem.map { Text($0.summary) }
    }
  }
}

extension JobLine.Problem {
  /// A few words that fit in a row.
  var summary: LocalizedStringResource {
    switch cause {
    case .unavailable: .loci("job.unavailable")
    case .network: .loci("job.network")
    case .outdated: .loci("job.failedOutdated")
    case .cookiesUnreadable: .loci("job.cookiesUnreadable")
    case .noArticleText: .loci("job.noArticleText")
    case nil:
      switch stage {
      case .resolve, .fetchPage: .loci("job.failedFetch")
      case .extract: .loci("job.failedExtract")
      case .findCover: .loci("job.failedCover")
      case .download: .loci("job.failedDownload")
      case .transcribe: .loci("job.failedRecognize")
      case .diarize: .loci("job.failedSeparateSpeakers")
      case .translate: .loci("job.failedTranslate")
      case .outline: .loci("job.failedOutline")
      }
    }
  }

  /// The whole of what went wrong, when the kind of trouble is known.
  var explanation: LocalizedStringResource? {
    switch cause {
    case .unavailable: .loci("job.unavailableDetail")
    case .network: .loci("job.networkDetail")
    case .outdated: .loci("job.outdatedDetail")
    case .cookiesUnreadable: .loci("job.cookiesUnreadableDetail")
    case .noArticleText, nil: nil
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
    case .bundledPi: "Pi"
    }
  }
}
