import Foundation

struct SourceLine: Equatable {
  enum Remark: Equatable {
    case documentation
    case plain
  }

  let number: Int
  /// The line with string contents and comments removed.
  let code: String
  let remark: Remark?
  let text: String
}

struct SourceFile {
  let path: String
  let module: String
  let lines: [SourceLine]

  init(path: String, module: String, text: String) {
    self.path = path
    self.module = module
    self.lines = Self.parse(text)
  }

  var imports: [(line: Int, name: String)] {
    lines.compactMap { line in
      guard let match = line.code.firstMatch(of: /^\s*(?:@\w+\s+)*import\s+(?:\w+\s+)?(\w+)/) else { return nil }
      return (line.number, String(match.1))
    }
  }

  static func parse(_ text: String) -> [SourceLine] {
    var scanner = Scanner()
    return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, raw in
      scanner.scan(String(raw), number: index + 1)
    }
  }

  private struct Scanner {
    private var insideBlockComment = false
    private var insideMultilineString = false

    mutating func scan(_ text: String, number: Int) -> SourceLine {
      let characters = Array(text)
      var code = ""
      var remark: SourceLine.Remark? = insideBlockComment ? .plain : nil
      var insideString = false
      var index = 0

      func starts(with token: String) -> Bool {
        characters[index...].starts(with: token)
      }

      scanning: while index < characters.count {
        if insideBlockComment {
          if starts(with: "*/") {
            insideBlockComment = false
            index += 2
          } else {
            index += 1
          }
        } else if insideMultilineString {
          if starts(with: "\"\"\"") {
            insideMultilineString = false
            index += 3
          } else {
            index += 1
          }
        } else if insideString {
          if characters[index] == "\\" {
            index += 2
            continue
          }
          if characters[index] == "\"" { insideString = false }
          index += 1
        } else if starts(with: "\"\"\"") {
          insideMultilineString = true
          code += "\"\""
          index += 3
        } else if characters[index] == "\"" {
          insideString = true
          code += "\"\""
          index += 1
        } else if starts(with: "///") {
          remark = .documentation
          break scanning
        } else if starts(with: "//") {
          remark = .plain
          break scanning
        } else if starts(with: "/*") {
          insideBlockComment = true
          remark = .plain
          index += 2
        } else {
          code.append(characters[index])
          index += 1
        }
      }
      return SourceLine(number: number, code: code, remark: remark, text: text)
    }
  }
}
