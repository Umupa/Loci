import Foundation
import LociModel

extension CourseBook {
  /// A course as its book: read as far as its lessons have been, and showing its stages while it is being built —
  /// until its first lesson is written, and again whenever Loci is at work on it.
  init(_ summary: CourseSummary) {
    let read = summary.lessonCount > 0 ? Double(summary.readCount) / Double(summary.lessonCount) : 0
    let building = summary.stage != .writing || summary.writtenCount == 0 || summary.isWorking
    let fraction: Double? =
      summary.stage == .writing && summary.lessonCount > 0
      ? Double(summary.writtenCount) / Double(summary.lessonCount) : nil
    self.init(
      id: summary.id, title: summary.title, subtitle: summary.subtitle ?? "", read: read,
      building: building ? Building(stage: summary.stage, fraction: fraction, working: summary.isWorking) : nil)
  }
}

extension BuilderShown {
  /// What the builder draws of `page`. `minutes` are the reading times of lessons written, as far as they are
  /// known; `shownLesson` is the text of the lesson written last, shown on the open book while nothing is being
  /// written.
  init(_ page: CoursePage, minutes: [Lesson.ID: Int], shownLesson: (id: Lesson.ID, markdown: String)?) {
    let course = page.course
    let working = page.activity != .idle
    let written = page.lessons.filter { $0.body == .written }.count
    let fraction: Double =
      switch course.stage {
      case .goal: Double(([course.goal.subtitle] + course.goal.lines).compactMap(\.self).count) / 6
      case .sources:
        course.sources.isEmpty ? 0 : Double(course.sources.filter(\.isRead).count) / Double(course.sources.count)
      case .writing: page.lessons.isEmpty ? 0 : Double(written) / Double(page.lessons.count)
      }
    let canGoOn =
      switch course.stage {
      case .goal: page.canBeginSources
      case .sources: page.canBeginWriting
      case .writing: page.firstReadableLesson != nil
      }
    self.init(
      stage: course.stage, fraction: fraction, working: working, title: course.goal.title ?? course.title,
      goal: course.goal, sealed: course.goalStatus == .confirmed || course.goalStatus == .ready,
      question: course.question,
      sources: course.sources.map { SourceShown($0, reading: working) },
      lessons: page.lessons.map { LessonLine($0, writing: page.activity.writingLesson, minutes: minutes[$0.id]) },
      leaf: Leaf(page, shownLesson: shownLesson), canGoOn: canGoOn)
  }
}

extension CourseActivity {
  /// The lesson Loci is writing now, if any.
  var writingLesson: Lesson.ID? {
    if case .writing(let lesson, _) = self { return lesson }
    return nil
  }
}

extension SourceShown {
  /// A course's source; one not read yet goes round while Loci is at work, as it may be reading it.
  init(_ source: CourseSource, reading: Bool) {
    self.init(
      id: source.id, title: source.title, kind: Kind(source.kind), detail: source.site,
      commit: source.commit?.description, url: source.url, read: source.isRead ? 1 : reading ? nil : 0)
  }
}

extension SourceShown.Kind {
  init(_ kind: CourseSource.Kind) {
    switch kind {
    case .paper: self = .paper
    case .video: self = .video
    case .repository: self = .repository
    case .page: self = .page
    }
  }
}

extension LessonLine {
  init(_ lesson: CourseLesson, writing: Lesson.ID?, minutes: Int?) {
    let state: State =
      lesson.id == writing ? .writing : lesson.body == .written ? .written(minutes: minutes) : .planned
    self.init(id: lesson.id, title: lesson.lesson.title, state: state)
  }
}

extension Leaf {
  /// The lesson Loci is writing, as far as it has got; or else the one written last.
  init?(_ page: CoursePage, shownLesson: (id: Lesson.ID, markdown: String)?) {
    let lessons = page.lessons.map(\.lesson)
    if case .writing(let lesson, let draft) = page.activity, let index = lessons.firstIndex(where: { $0.id == lesson })
    {
      self.init(
        number: index + 1, title: lessons[index].title,
        paragraphs: Array(Self.paragraphs(draft ?? "").suffix(3)), writing: true)
    } else if let shownLesson, let index = lessons.firstIndex(where: { $0.id == shownLesson.id }) {
      self.init(
        number: index + 1, title: lessons[index].title,
        paragraphs: Array(Self.paragraphs(shownLesson.markdown).prefix(3)), writing: false)
    } else {
      return nil
    }
  }

  /// The paragraphs of Markdown as plain words: headings, pictures, code and rules left out, links kept as their
  /// words, marks of emphasis and quotation taken off.
  static func paragraphs(_ markdown: String) -> [String] {
    var inCode = false
    var kept: [String] = []
    for block in markdown.components(separatedBy: "\n\n") {
      let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
      guard let first = lines.first?.trimmingCharacters(in: .whitespaces) else { continue }
      if first.hasPrefix("```") {
        inCode = !(lines.count > 1 && lines.last?.hasPrefix("```") == true)
        continue
      }
      if inCode {
        if lines.contains(where: { $0.hasPrefix("```") }) { inCode = false }
        continue
      }
      if first.hasPrefix("#") || first.hasPrefix("![") || first.hasPrefix("---") || first.hasPrefix("|") { continue }
      let words = lines.map { $0.trimmingCharacters(in: .whitespaces).replacing(/^(>|[-*+]|\d+\.)\s+/, with: "") }
        .joined(separator: " ")
        .replacing(/!\[[^\]]*\]\([^)]*\)/, with: "")
        .replacing(/\[([^\]]*)\]\([^)]*\)/) { String($0.output.1) }
        .replacing(/\*\*|__|`/, with: "")
      if !words.isEmpty { kept.append(words) }
    }
    return kept
  }
}
