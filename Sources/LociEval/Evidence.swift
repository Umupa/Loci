import Foundation
import LociModel

/// What one scenario's mentor made, and when.
struct Evidence: Sendable {
  struct WrittenLesson: Hashable, Sendable {
    let slug: String
    let title: String
    /// The sources listed at the top of the lesson file: item ids or links.
    let sources: [String]
    let body: String
  }

  let scenario: Scenario
  let catalog: Catalog?
  let lessons: [WrittenLesson]
  let conversation: [Message]
  /// Seconds from creating the mentor.
  let catalogAfter: Double?
  let firstLessonAfter: Double?
  /// The mentor's first turn did not end by itself in time and was stopped.
  let stoppedFirstTurn: Bool
  /// The reply to the probe question.
  let probeAnswer: String
}
