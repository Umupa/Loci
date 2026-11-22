import Foundation

public struct CourseQuestion: Hashable, Codable, Sendable, Identifiable {
  public struct Option: Hashable, Codable, Sendable {
    public let title: String
    public let detail: String

    public init(title: String, detail: String) throws {
      self.title = try CourseGoal.line(title, field: "option title")
      self.detail = try CourseGoal.line(detail, field: "option detail")
    }

    private enum CodingKeys: String, CodingKey {
      case title, detail
    }

    public init(from decoder: any Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      self = try decoder.validated {
        try Option(
          title: values.decode(String.self, forKey: .title), detail: values.decode(String.self, forKey: .detail))
      }
    }
  }

  public enum Purpose: Hashable, Codable, Sendable {
    case followUp(field: CourseGoal.Field?)
    case confirmation
  }

  public struct Draft: Hashable, Codable, Sendable {
    public let question: String
    public let options: [Option]
    public let multiple: Bool
    public let purpose: Purpose

    public init(
      question: String, options: [Option], multiple: Bool, purpose: Purpose = .followUp(field: nil)
    ) throws {
      guard (2...4).contains(options.count) else {
        throw ModelError("options must contain 2 to 4 answers")
      }
      if purpose == .confirmation, multiple || options.count != 2 {
        throw ModelError("confirmation takes two options in order: confirm, then ask to revise")
      }
      self.question = try question.trimmingCharacters(in: .whitespacesAndNewlines).requiringText("question")
      self.options = options
      self.multiple = multiple
      self.purpose = purpose
    }

    private enum CodingKeys: String, CodingKey {
      case question, options, multiple, field, confirmation
    }

    public init(from decoder: any Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      self = try decoder.validated {
        let field = try values.decodeIfPresent(CourseGoal.Field.self, forKey: .field)
        let confirmation = try values.decodeIfPresent(Bool.self, forKey: .confirmation) ?? false
        guard !confirmation || field == nil else {
          throw ModelError("leave field out of a confirmation question")
        }
        return try Draft(
          question: values.decode(String.self, forKey: .question),
          options: values.decode([Option].self, forKey: .options),
          multiple: values.decode(Bool.self, forKey: .multiple),
          purpose: confirmation ? .confirmation : .followUp(field: field))
      }
    }

    public func encode(to encoder: any Encoder) throws {
      var values = encoder.container(keyedBy: CodingKeys.self)
      try values.encode(question, forKey: .question)
      try values.encode(options, forKey: .options)
      try values.encode(multiple, forKey: .multiple)
      switch purpose {
      case .followUp(let field): try values.encodeIfPresent(field, forKey: .field)
      case .confirmation: try values.encode(true, forKey: .confirmation)
      }
    }
  }

  public let id: EntityID
  public let draft: Draft

  public init(id: EntityID, draft: Draft) {
    self.id = id
    self.draft = draft
  }

  func event(for answer: CourseAnswer) throws -> CourseEvent {
    switch (draft.purpose, answer) {
    case (.confirmation, .option(0)): return .confirmedGoal
    case (.confirmation, .option(1)): return .askedToReviseGoal
    case (.confirmation, _): throw ModelError("select confirm or ask to revise")
    case (.followUp, .text(let answer)):
      let text = try answer.trimmingCharacters(in: .whitespacesAndNewlines).requiringText("answer")
      return .answered(question: draft.question, answers: [text])
    case (.followUp, .option(let index)) where !draft.multiple:
      return .answered(question: draft.question, answers: try titles(at: [index]))
    case (.followUp, .options(let indices)) where draft.multiple:
      return .answered(question: draft.question, answers: try titles(at: indices.sorted()))
    default: throw ModelError(draft.multiple ? "choose one or more options" : "choose a single option")
    }
  }

  private func titles(at indices: [Int]) throws -> [String] {
    guard !indices.isEmpty, Set(indices).count == indices.count, indices.allSatisfy(draft.options.indices.contains)
    else { throw ModelError("choose distinct options from the current question") }
    return indices.map { draft.options[$0].title }
  }
}

public enum CourseAnswer: Hashable, Codable, Sendable {
  case option(Int)
  case options([Int])
  case text(String)
}
