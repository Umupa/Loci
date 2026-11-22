enum Batches {
  static func pieces<Value>(of values: [Value], size: Int) -> [[Value]] {
    stride(from: 0, to: values.count, by: size).map { Array(values[$0..<min($0 + size, values.count)]) }
  }

  static func run<Input: Sendable, Output: Sendable, Failure: Error>(
    _ inputs: [Input], parallelism: Int, isolation: isolated (any Actor)? = #isolation,
    work: @escaping @Sendable (Int, Input) async throws(Failure) -> Output,
    keep: (Output) async throws(Failure) -> Void
  ) async throws(Failure) {
    if parallelism == 1 {
      for (index, input) in inputs.enumerated() {
        if Task.isCancelled { return }
        try await keep(work(index, input))
      }
      return
    }
    let failure: Failure? = await withTaskGroup(
      of: (Int, Result<Output, Failure>).self, isolation: isolation
    ) { group in
      var next = 0
      var finished: [Int: Result<Output, Failure>] = [:]
      for index in 0..<min(parallelism, inputs.count) {
        let input = inputs[index]
        group.addTask { (index, await result { () async throws(Failure) in try await work(index, input) }) }
      }
      while let (index, answer) = await group.next() {
        if Task.isCancelled {
          group.cancelAll()
          return nil
        }
        finished[index] = answer
        while let answer = finished.removeValue(forKey: next) {
          do throws(Failure) {
            try await keep(answer.get())
          } catch {
            group.cancelAll()
            return error
          }
          let following = next + parallelism
          if following < inputs.count {
            let input = inputs[following]
            group.addTask { (following, await result { () async throws(Failure) in try await work(following, input) }) }
          }
          next += 1
        }
      }
      return nil
    }
    if let failure { throw failure }
  }

  private static func result<Value: Sendable, Failure: Error>(
    _ body: () async throws(Failure) -> Value
  ) async -> Result<Value, Failure> {
    do {
      return .success(try await body())
    } catch {
      return .failure(error)
    }
  }
}
