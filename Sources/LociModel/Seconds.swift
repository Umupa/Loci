/// Times in item files are seconds with up to three decimals, kept to the millisecond.
enum Seconds {
  static func duration(_ seconds: Double) -> Duration {
    .milliseconds(Int((seconds * 1000).rounded()))
  }

  static func number(_ duration: Duration) -> Double {
    Double(duration.roundedMilliseconds) / 1000
  }
}
