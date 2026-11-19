/// The value last made, made again only when what it is made from changes.
@MainActor
final class Remembered<Input: Equatable, Output> {
  private let make: (Input) -> Output
  private var last: (input: Input, output: Output)?

  init(_ make: @escaping (Input) -> Output) {
    self.make = make
  }

  func callAsFunction(_ input: Input) -> Output {
    if let last, last.input == input { return last.output }
    let output = make(input)
    last = (input, output)
    return output
  }
}
