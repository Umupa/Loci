import Foundation
import LociModel

extension FakeHost {
  func timers() async throws(HostError) -> Timers { sampleTimers.timers }
  func runs(of schedule: ScheduleRef, limit: Int) async throws(HostError) -> [Run] {
    Array((sampleTimers.runs[schedule] ?? []).prefix(limit))
  }
  func pauseSchedule(_ command: PauseSchedule) async throws(HostError) -> Done { Done() }
  func changeSchedule(_ command: ChangeSchedule) async throws(HostError) -> ScheduleEntry {
    throw .notFound(command.schedule.key)
  }
  func removeSchedule(_ command: RemoveSchedule) async throws(HostError) -> Done { Done() }
  func addSchedule(_ command: AddSchedule) async throws(HostError) -> ScheduleEntry {
    throw .invalidRequest("schedules are added by the companion")
  }
  func addFollowUp(_ command: AddFollowUp) async throws(HostError) -> FollowUp {
    throw .invalidRequest("follow-ups are set by the companion")
  }
  func cancelFollowUp(_ command: CancelFollowUp) async throws(HostError) -> Done { Done() }
}

/// Timers a fake host serves, told against `now`.
struct SampleTimers {
  let timers: Timers
  let runs: [ScheduleRef: [Run]]

  /// The panels the design's schedules put what they find in.
  static let panels = PanelColumn(
    slots: [("cubesandbox", "CubeSandbox"), ("week-tasks", "本周任务"), ("community", "社区")].map { name, title in
      .panel(Panel(name: name, title: title, follow: title, body: .rows([.sentence(title)])))
    })

  static let none = SampleTimers(timers: Timers(schedules: [], followUps: [], next: nil), runs: [:])

  /// 2026-11-24 15:30 on this Mac's clock.
  static let now: Date = {
    DateComponents(calendar: .current, year: 2026, month: 11, day: 24, hour: 15, minute: 30).date ?? Date()
  }()

  /// The design's timers: two schedules on panels, one in the notes, one paused, and three follow-ups.
  static let design: SampleTimers = {
    func at(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Timestamp {
      let day = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
      let time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
      return Timestamp(time)
    }
    func time(_ hour: Int) -> TimeOfDay { TimeOfDay(hour: hour, minute: 0) ?? TimeOfDay(of: at(0, hour), in: .current) }
    let cube = ScheduleRef.schedule(EntityID())
    let papers = ScheduleRef.schedule(EntityID())
    let v2ex = ScheduleRef.schedule(EntityID())
    let tasks = ScheduleRef.panel("week-tasks")
    let schedules = [
      ScheduleEntry(
        ref: cube, name: "cubesandbox-news", title: "CubeSandbox 的动态", every: .day(at: time(21)),
        destination: .panel("cubesandbox"), paused: false, next: at(0, 21),
        lastSummary: "v0.9 发布，快照恢复从 1.8s 降到 0.6s；#412 还没人回。", lastRun: at(-1, 21)),
      ScheduleEntry(
        ref: tasks, name: "week-tasks", title: "本周的任务", every: .hour, destination: .panel("week-tasks"),
        paused: false, next: at(0, 16), lastSummary: "7 件里还剩 3 件，「沙箱学习笔记」周五到期。", lastRun: at(0, 14)),
      ScheduleEntry(
        ref: papers, name: "scheduling-papers", title: "调度论文新进展", every: .week(.monday, at: time(9)),
        destination: .notes, paused: false, next: at(6, 9), lastSummary: "OSDI 收了两篇 gang scheduling，记进笔记了。",
        lastRun: at(-8, 9)),
      ScheduleEntry(
        ref: v2ex, name: "v2ex-sandbox", title: "V2EX 和 Hacker News 上关于沙箱隔离与冷启动的讨论 🧪", every: .day(at: time(12)),
        destination: .panel("community"), paused: true, next: nil, lastSummary: "两帖在比 gVisor 和 Kata，没新观点。",
        lastRun: at(-5, 12)),
    ]
    let followUps = [
      FollowUp(
        id: EntityID(), due: at(0, 18), what: "看看你下午那版 Raft 图解有没有画错 term。", conversation: nil, createdAt: at(0, 14)),
      FollowUp(id: EntityID(), due: at(3, 10), what: "#412 有没有人回复。", conversation: nil, createdAt: at(-1, 21)),
      FollowUp(id: EntityID(), due: at(7, 9), what: "E2B 说月底开源新的快照格式，到时候去看。", conversation: nil, createdAt: at(-2, 22)),
    ]
    func run(_ days: Int, _ outcome: Run.Outcome) -> Run {
      Run(
        id: EntityID(), kind: .timers(Run.Timed(.schedule(EntityID()))), startedAt: at(days, 21), outcome: outcome,
        record: "")
    }
    let runs = [
      run(
        -1,
        .finished(
          summary: "v0.9 发布：快照恢复从 1.8 秒降到 0.6 秒，换了内存页的预取方式。#412 还没人回。",
          sources: [
            "https://github.com/TencentCloud/CubeSandbox/releases", "https://cloud.tencent.com/developer/article/2471",
          ])),
      run(-2, .finished(summary: "没有新东西。", sources: ["https://github.com/TencentCloud/CubeSandbox"])),
      run(-3, .failed("Codex 没起来，重试三次都失败。", tries: 3)),
      run(
        -4,
        .finished(
          summary: "有人提了 Firecracker 对比的 issue，作者回了数量级：冷启动 125ms 对 60ms。",
          sources: ["https://github.com/TencentCloud/CubeSandbox/issues/398", "资料库 · E2B 架构"])),
    ]
    return SampleTimers(
      timers: Timers(schedules: schedules, followUps: followUps, next: at(0, 16)), runs: [cube: runs])
  }()
}
