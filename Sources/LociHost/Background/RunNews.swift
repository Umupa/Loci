import Foundation
import LociModel
import LociStore

/// What a home's conversation is told of its runs in the background: runs since the person last talked, and
/// every follow-up that came due and was not yet told, done or not. A project's runs are told only in the
/// project, the chat's only in the main conversation.
struct RunNews {
  /// The most runs listed.
  static let limit = 10

  var runs: [String] = []
  var followUps: [String] = []
  /// The follow-up runs to remember as told once the prefix is sent.
  var told: [Run.ID] = []
}

extension AgentContext {
  func runNews(since moment: Timestamp, in home: Home) -> RunNews {
    var news = RunNews()
    let timeZone = environment.timeZone
    let today = Day(containing: environment.now(), in: timeZone)
    func when(_ run: Run) -> String {
      let day = Day(containing: run.startedAt, in: timeZone)
      let time = TimeOfDay(of: run.startedAt, in: timeZone)
      return day == today ? "\(time)" : "\(day) \(time)"
    }
    let files = store.home(home)
    let ended = ((try? database.runs(startedAfter: moment)) ?? []).filter { run in
      if case .running = run.outcome { return false }
      return run.kind.home == home && run.kind.sources.contains { $0.schedule != nil }
    }
    news.runs = ended.suffix(RunNews.limit).map { run in
      let names = run.kind.sources.compactMap { source -> String? in
        switch source {
        case .schedule(let id, _): ((try? database.schedule(id)) ?? nil)?.name
        case .panel(let name, _, _): "panel \(name)"
        case .followUp, .review: nil
        }
      }
      return "- \(when(run)) \(names.joined(separator: ", ")): \(outcome(of: run)) (\(files.local(run.record)))"
    }
    for run in (try? database.untoldFollowUpRuns()) ?? [] where run.kind.home == home {
      for case .followUp(let id, _) in run.kind.sources {
        let what = ((try? database.followUp(id)) ?? nil)?.what ?? id.description
        news.followUps.append("- \(when(run)) \"\(what)\": \(outcome(of: run)) (\(files.local(run.record)))")
      }
      news.told.append(run.id)
    }
    return news
  }

  private func outcome(of run: Run) -> String {
    switch run.outcome {
    case .finished(let summary, _): summary
    case .failed(let reason, let tries): "not done; it failed \(tries) time(s): \(reason)"
    case .running: "still going"
    }
  }
}
