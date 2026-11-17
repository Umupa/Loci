extension Duration {
  var roundedMilliseconds: Int {
    let (seconds, attoseconds) = components
    return Int(seconds) * 1000 + Int((Double(attoseconds) / 1e15).rounded())
  }
}
