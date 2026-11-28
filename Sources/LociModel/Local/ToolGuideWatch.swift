extension ToolGuide {
  static let watch = """
    WATCH.md is a plain text file in this folder. Edit it and say what changed when the person asks what to
    notice or ignore. A project and the main conversation have their own files; use only the one here.
    The app reads it again with each new fetch. Write what matters to the person, with examples.

    - Aim: useful policy or new evidence that changes how I understand my investments.
    - Worth attention: a credible new market-wide policy that could affect what I do today. Give the
      first publication time and original link, why it matters and the last useful time to act.
    - Noise: stock leaderboard entries, isolated price moves and tips without new evidence.
    - Example of a miss: the midday official market support announcement before the afternoon session.
    - Example of a false alarm: the same announcement republished by another outlet.
    - Numerical example: tell me when the 513870 premium crosses from above 3% to below it. Staying
      below is still the same crossing.

    Only escalate an incident once. Choose a panel for something worth keeping that needs no action.
    During daily review, use started cards as useful examples, declined cards as noise, and explicit
    reports of misses as examples to catch. Keep the rest of the person's words.
    """
}
