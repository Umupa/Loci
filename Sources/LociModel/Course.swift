import Foundation

public enum CourseStage: String, Hashable, Codable, Sendable {
  case goal, sources, writing
}

public struct Course: Hashable, Codable, Sendable, Identifiable {
  public enum GoalStatus: String, Hashable, Codable, Sendable {
    case interview, awaitingConfirmation, confirmed, ready
  }

  public struct PendingEvent: Hashable, Codable, Sendable {
    public let id: EntityID
    public let event: CourseEvent
  }

  public let id: EntityID
  public private(set) var title: String
  public private(set) var stage: CourseStage
  public private(set) var goal: CourseGoal
  public private(set) var goalStatus: GoalStatus
  public private(set) var question: CourseQuestion?
  public private(set) var sources: [CourseSource]
  public private(set) var lessons: [Lesson]
  public private(set) var readLessons: Set<Lesson.ID>
  public let createdAt: Timestamp
  public private(set) var pendingEvents: [PendingEvent] = []
  public private(set) var workPaused = false
  private var removedSourceURLs: Set<URL> = []

  public init(id: EntityID, topic: String, createdAt: Timestamp) throws {
    self.id = id
    self.createdAt = createdAt
    title = try CourseGoal.line(topic, field: "course topic")
    stage = .goal
    goal = try CourseGoal(title: title)
    goalStatus = .interview
    sources = []
    lessons = []
    readLessons = []
  }

  public mutating func ask(_ question: CourseQuestion) throws {
    guard stage == .goal, goalStatus == .interview || goalStatus == .awaitingConfirmation else {
      throw ModelError("a follow-up belongs to the goal interview")
    }
    self.question = question
    goalStatus = question.draft.purpose == .confirmation ? .awaitingConfirmation : .interview
  }

  public mutating func answer(question id: EntityID, with answer: CourseAnswer) throws -> CourseEvent {
    guard stage == .goal, let question, question.id == id else {
      throw ModelError("answer the course's current question")
    }
    let event = try question.event(for: answer)
    self.question = nil
    goalStatus = event == .confirmedGoal ? .confirmed : .interview
    return event
  }

  public mutating func updateGoal(_ changes: CourseGoal) throws {
    guard stage == .goal, goalStatus != .ready else { throw ModelError("the course goal is already ready") }
    goal = try goal.applying(changes)
    if let changedTitle = changes.title { title = changedTitle }
  }

  public mutating func markGoalReady() throws {
    guard stage == .goal else { throw ModelError("ready belongs to the goal stage") }
    if goalStatus == .ready { return }
    guard goalStatus == .confirmed else { throw ModelError("ask the person to confirm the goal first") }
    guard goal.subtitle != nil, goal.length != nil else {
      throw ModelError("set the goal's subtitle and length before marking it ready")
    }
    goalStatus = .ready
  }

  public mutating func beginSources() throws {
    guard stage == .goal, goalStatus == .ready else { throw ModelError("finish the goal before gathering sources") }
    stage = .sources
  }

  public mutating func addSource(
    _ draft: CourseSource.Draft, id: EntityID, chosenByReader: Bool = false
  ) throws -> CourseSource {
    guard stage != .goal else { throw ModelError("begin gathering sources before adding a source") }
    if chosenByReader {
      removedSourceURLs.remove(draft.url)
    } else if removedSourceURLs.contains(draft.url) {
      throw ModelError("the person removed this source; use a different link")
    }
    if let index = sources.firstIndex(where: { $0.url == draft.url }) {
      let updated = sources[index].updated(with: draft)
      sources[index] = updated
      return updated
    }
    guard !sources.contains(where: { $0.id == id }) else { throw ModelError("that source ID is already in the course") }
    let source = CourseSource(id: id, from: draft)
    sources.append(source)
    return source
  }

  public mutating func markSourceRead(_ source: EntityID) throws {
    guard let index = sources.firstIndex(where: { $0.id == source }) else {
      throw ModelError("find the source ID with loci course source list")
    }
    sources[index] = sources[index].read()
  }

  public mutating func removeSource(_ source: EntityID) throws -> CourseSource {
    guard stage == .sources else { throw ModelError("remove sources during the sources stage") }
    guard let index = sources.firstIndex(where: { $0.id == source }) else {
      throw ModelError("that source is no longer in the course")
    }
    let removed = sources.remove(at: index)
    removedSourceURLs.insert(removed.url)
    return removed
  }

  public mutating func beginWriting() throws {
    if stage == .writing, lessons.isEmpty { return }
    guard stage == .sources, !sources.isEmpty else { throw ModelError("add a source before beginning to write") }
    stage = .writing
  }

  public mutating func replacePlan(_ lessons: [Lesson], keepingWritten written: Set<Lesson.ID>) throws {
    guard stage == .writing else { throw ModelError("begin writing before planning the lessons") }
    let ids = lessons.map(\.id)
    guard !ids.isEmpty, Set(ids).count == ids.count else {
      throw ModelError("give the plan at least one lesson and a different ID for each title")
    }
    let protected = written.union(readLessons)
    let oldWritten = self.lessons.filter { protected.contains($0.id) }
    let newWritten = lessons.filter { protected.contains($0.id) }
    guard oldWritten == newWritten else {
      throw ModelError("keep the IDs, titles and relative order of lessons already written")
    }
    self.lessons = lessons
  }

  public mutating func markLessonRead(_ lesson: Lesson.ID) throws {
    guard lessons.contains(where: { $0.id == lesson }) else { throw ModelError("that lesson is not in the course") }
    readLessons.insert(lesson)
  }

  public mutating func keepEvent(_ event: CourseEvent, id: EntityID) -> PendingEvent {
    workPaused = false
    if let existing = pendingEvents.first(where: { $0.event == event }) { return existing }
    let pending = PendingEvent(id: id, event: event)
    pendingEvents.append(pending)
    return pending
  }

  public mutating func completeEvent(_ id: EntityID) {
    pendingEvents.removeAll { $0.id == id }
  }

  public mutating func setWorkPaused(_ paused: Bool) {
    workPaused = paused
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, stage, goal, goalStatus, question, sources, lessons, readLessons, createdAt
    case pendingEvents, workPaused, removedSourceURLs
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(EntityID.self, forKey: .id)
    title = try values.decode(String.self, forKey: .title)
    stage = try values.decode(CourseStage.self, forKey: .stage)
    goal = try values.decode(CourseGoal.self, forKey: .goal)
    goalStatus = try values.decode(GoalStatus.self, forKey: .goalStatus)
    question = try values.decodeIfPresent(CourseQuestion.self, forKey: .question)
    sources = try values.decode([CourseSource].self, forKey: .sources)
    lessons = try values.decode([Lesson].self, forKey: .lessons)
    readLessons = Set(try values.decode([Lesson.ID].self, forKey: .readLessons))
    createdAt = try values.decode(Timestamp.self, forKey: .createdAt)
    pendingEvents = try values.decodeIfPresent([PendingEvent].self, forKey: .pendingEvents) ?? []
    workPaused = try values.decodeIfPresent(Bool.self, forKey: .workPaused) ?? false
    removedSourceURLs = Set(try values.decodeIfPresent([URL].self, forKey: .removedSourceURLs) ?? [])
    try decoder.validated { try validate() }
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(title, forKey: .title)
    try values.encode(stage, forKey: .stage)
    try values.encode(goal, forKey: .goal)
    try values.encode(goalStatus, forKey: .goalStatus)
    try values.encodeIfPresent(question, forKey: .question)
    try values.encode(sources, forKey: .sources)
    try values.encode(lessons, forKey: .lessons)
    try values.encode(readLessons.sorted { $0.description < $1.description }, forKey: .readLessons)
    try values.encode(createdAt, forKey: .createdAt)
    if !pendingEvents.isEmpty { try values.encode(pendingEvents, forKey: .pendingEvents) }
    if workPaused { try values.encode(workPaused, forKey: .workPaused) }
    if !removedSourceURLs.isEmpty {
      try values.encode(removedSourceURLs.sorted { $0.absoluteString < $1.absoluteString }, forKey: .removedSourceURLs)
    }
  }

  private func validate() throws {
    guard title == (try CourseGoal.line(title, field: "course title")), goal.title == nil || goal.title == title else {
      throw ModelError("course and goal titles must match")
    }
    let lessonIDs = Set(lessons.map(\.id))
    guard lessonIDs.count == lessons.count, readLessons.isSubset(of: lessonIDs) else {
      throw ModelError("the plan needs unique lesson IDs and must include all read lessons")
    }
    guard Set(sources.map(\.id)).count == sources.count, Set(sources.map(\.url)).count == sources.count else {
      throw ModelError("course sources must have unique IDs and URLs")
    }
    guard stage == .goal || goalStatus == .ready,
      stage == .writing || lessons.isEmpty,
      stage != .writing || !sources.isEmpty,
      stage != .goal || sources.isEmpty
    else { throw ModelError("the course contents do not match its stage") }
    switch goalStatus {
    case .interview:
      if question?.draft.purpose == .confirmation { throw ModelError("the goal is awaiting confirmation") }
    case .awaitingConfirmation:
      guard question?.draft.purpose == .confirmation else { throw ModelError("the confirmation question is missing") }
    case .confirmed, .ready:
      guard question == nil else { throw ModelError("a confirmed goal has no pending question") }
    }
    if goalStatus == .ready, goal.subtitle == nil || goal.length == nil {
      throw ModelError("a ready goal needs a subtitle and length")
    }
  }
}
