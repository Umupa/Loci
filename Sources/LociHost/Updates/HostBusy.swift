import LociModel

/// What a host is busy with that restarting Loci would cut short, for the updater to wait on.
public enum HostBusy {
  /// The library stages that a restart would set back.
  static let heavyStages: Set<Job.Stage> = [.download, .transcribe, .diarize]

  /// What `host` is busy with now, then again whenever that changes; `nil` while it is idle. It follows the
  /// host across a reset of the data folder, when the deferred host hands over to a new one.
  public static func of(_ host: any LociModel.Host) -> AsyncStream<Busy?> {
    of(
      status: {
        AsyncStream { continuation in
          let forwarding = Task {
            for await case .value(let status) in host.subscribe(LociWorking()) { continuation.yield(status.work) }
            continuation.finish()
          }
          continuation.onTermination = { _ in forwarding.cancel() }
        }
      },
      jobs: {
        AsyncStream { continuation in
          let forwarding = Task {
            for await case .value(let jobs) in host.subscribe(AllJobs()) { continuation.yield(jobs) }
            continuation.finish()
          }
          continuation.onTermination = { _ in forwarding.cancel() }
        }
      })
  }

  /// Merges what the companion is doing with the library's jobs. A subscription that ends after it delivered
  /// is made again, with its last value forgotten, since the host it came from has gone; one that ends without
  /// delivering anything is not, so a host that cannot be reached is not asked over and over.
  static func of(
    status: @escaping @Sendable () -> AsyncStream<LociWork?>, jobs: @escaping @Sendable () -> AsyncStream<[Job]>
  ) -> AsyncStream<Busy?> {
    let (stream, continuation) = AsyncStream.makeStream(of: Busy?.self, bufferingPolicy: .bufferingNewest(1))
    let watching = Task {
      let reports = AsyncStream<Report> { reports in
        let following = [
          follow(status, as: Report.status, idle: .status(nil), into: reports),
          follow(jobs, as: Report.jobs, idle: .jobs([]), into: reports),
        ]
        reports.onTermination = { _ in for task in following { task.cancel() } }
      }
      var work: LociWork?
      var running: [Job] = []
      var last: Busy??
      for await report in reports {
        switch report {
        case .status(let now): work = now
        case .jobs(let now): running = now
        }
        let now = busy(work: work, jobs: running)
        if last != .some(now) { continuation.yield(now) }
        last = now
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in watching.cancel() }
    return stream
  }

  private static func follow<Value: Sendable>(
    _ subscribe: @escaping @Sendable () -> AsyncStream<Value>, as report: @escaping @Sendable (Value) -> Report,
    idle: Report, into reports: AsyncStream<Report>.Continuation
  ) -> Task<Void, Never> {
    Task {
      while !Task.isCancelled {
        var delivered = false
        for await value in subscribe() {
          delivered = true
          reports.yield(report(value))
        }
        guard delivered else { return }
        reports.yield(idle)
      }
    }
  }

  private enum Report: Sendable {
    case status(LociWork?)
    case jobs([Job])
  }

  /// Answering comes first, then a background run, then the library.
  static func busy(work: LociWork?, jobs: [Job]) -> Busy? {
    switch work {
    case .answering: return .answering
    case .refreshing, .reviewing, .looking, .unspecified: return .running
    case .saving: return .library
    case nil: break
    }
    let heavy = jobs.contains { job in
      guard case .running = job.state else { return false }
      return heavyStages.contains(job.stage)
    }
    return heavy ? .library : nil
  }
}
