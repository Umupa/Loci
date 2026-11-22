import Foundation
import LociModel

/// Everything the builder draws of a course being built, apart from its conversation.
struct BuilderShown: Equatable {
  var stage: CourseStage
  /// How far the current stage has got, from 0 to 1.
  var fraction: Double = 0
  /// Loci is at work on the course now.
  var working = false
  var title: String
  var goal: CourseGoal
  /// The goal is settled: the person agreed with Loci's account of it.
  var sealed = false
  var question: CourseQuestion?
  var sources: [SourceShown] = []
  var lessons: [LessonLine] = []
  /// The lesson on the open book's right-hand page.
  var leaf: Leaf?
  /// Whether the button at the foot can be pressed.
  var canGoOn = false
}

extension CourseGoal {
  /// The five lines under the title page's rule, in the order they are drawn.
  var lines: [String?] { [purpose, focus, known, depth, length] }

  /// The line of `field`, when it has one under the rule.
  static func line(of field: CourseGoal.Field) -> Int? {
    switch field {
    case .purpose: 0
    case .focus: 1
    case .known: 2
    case .depth: 3
    case .length: 4
    case .title, .subtitle: nil
    }
  }

  /// The line an answer to `question` flies to: the one it fills, or else the first still empty.
  func line(answering question: CourseQuestion.Draft) -> Int? {
    if case .followUp(let field?) = question.purpose, let line = Self.line(of: field) { return line }
    return lines.firstIndex { $0 == nil }
  }
}

extension CourseQuestion.Draft {
  /// How it is answered: one card, any number of boxes, or a reply to Loci's account of the goal.
  var answering: Answering {
    if purpose == .confirmation { return .reply }
    return multiple ? .many : .one
  }

  enum Answering {
    case one, many, reply
  }

  /// The title of the answer at `index`, or nothing when there is none.
  func title(of index: Int) -> String {
    options.indices.contains(index) ? options[index].title : ""
  }
}

/// A source on the desk.
struct SourceShown: Equatable, Identifiable {
  let id: EntityID
  let title: String
  let kind: Kind
  /// Where it is from and what it is: the site, and a year, a length or a language.
  let detail: String
  /// The commit a repository is pinned at.
  var commit: String?
  var url: URL?
  /// How much of it Loci has read; 1 is all of it, `nil` while it is being read and how far cannot be told.
  var read: Double? = 0

  enum Kind: Equatable {
    case paper, video, repository, page
  }
}

/// A lesson on a course's contents.
struct LessonLine: Equatable, Identifiable {
  let id: Lesson.ID
  let title: String
  var state: State

  enum State: Equatable {
    case planned
    case writing
    /// Written, and how many minutes it takes to read, once that is known.
    case written(minutes: Int?)
  }
}

/// The lesson being written on the right-hand page, paragraph by paragraph.
struct Leaf: Equatable {
  let number: Int
  let title: String
  let paragraphs: [String]
  /// More of it is still coming.
  var writing: Bool
}
