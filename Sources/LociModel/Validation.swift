extension String {
  func requiringText(_ field: String) throws -> String {
    guard !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ModelError("\(field) is empty") }
    return self
  }

  var isLowercaseHex: Bool {
    !isEmpty && utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
  }

  var isASCIIDigits: Bool {
    !isEmpty && utf8.allSatisfy { (0x30...0x39).contains($0) }
  }
}

extension String? {
  func requiringText(_ field: String) throws -> String? {
    try map { try $0.requiringText(field) }
  }
}

extension String {
  func leftPadded(to width: Int) -> String {
    String(repeating: "0", count: max(0, width - count)) + self
  }
}
