/// One live conversation with a running agent program. It runs one turn at a time.
public protocol AgentSession: Sendable {
  var handle: SessionHandle { get }

  /// Starts a turn. Throws `.turnInProgress` while another one is running.
  func send(_ text: String) async throws(AgentError) -> Turn

  /// Stops the running turn and returns once it has ended. Does nothing when no turn is running.
  func interrupt() async

  /// Answers a permission request from the running turn. An unknown or already answered request is ignored.
  func answer(_ request: PermissionRequest.ID, with answer: PermissionAnswer) async

  /// Ends the program. The handle stays valid for `SessionConfiguration.resume`.
  func close() async
}

public struct Turn: Sendable {
  /// Finishes after exactly one `.ended`, which is always the last element.
  public let events: AsyncStream<AgentEvent>

  /// Drivers make turns with their own pipe; this is for sessions written outside the drivers, such as fakes.
  public init(events: AsyncStream<AgentEvent>) {
    self.events = events
  }
}
