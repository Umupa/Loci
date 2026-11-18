/// Messages waiting for one reader, in order. `take` returns `nil` once the mailbox is finished and empty,
/// or when the reading task is cancelled.
actor Mailbox<Element: Sendable> {
  private var queued: [Element] = []
  private var reader: CheckedContinuation<Element?, Never>?
  private var isFinished = false

  func put(_ element: Element) {
    guard !isFinished else { return }
    if let reader {
      self.reader = nil
      reader.resume(returning: element)
    } else {
      queued.append(element)
    }
  }

  func finish() {
    isFinished = true
    reader?.resume(returning: nil)
    reader = nil
  }

  func take() async -> Element? {
    if !queued.isEmpty { return queued.removeFirst() }
    guard !isFinished, !Task.isCancelled else { return nil }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { reader = $0 }
    } onCancel: {
      Task { await self.finishReading() }
    }
  }

  private func finishReading() {
    reader?.resume(returning: nil)
    reader = nil
  }
}
