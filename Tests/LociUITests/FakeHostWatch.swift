import LociModel

/// What the chat and each project watch for: the chat's as the investing example reads, a project's empty
/// but for its heading. What is saved is accepted and forgotten.
extension FakeHost {
  func watch(of home: Home) async throws(HostError) -> String {
    home == .chat ? FakeHost.chatWatch : "# Watch\n"
  }

  func saveWatch(_ command: SaveWatch) async throws(HostError) -> Done { Done() }

  static let chatWatch = """
    # Watch

    ## 要告诉我

    - 稳市政策、国家队入场：首发时间和出处，赶在开盘前。
    - **513870** 溢价跌破 3% 时告诉我；一直低于 3% 不再提。

    ## 噪音

    - 龙虎榜、个股异动、喊单。
    - 同一件事换个媒体或标题又出现。
    """
}
