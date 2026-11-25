import Foundation

/// Lays tiles out so each one's area follows its weight, as near square as they will go: rows are filled
/// along the shorter side while that makes the worst tile in the row squarer.
enum HeatLayout {
  /// One rectangle for each weight, in the order given; weights that are not positive get none of the area.
  static func tiles(_ weights: [Double], in size: CGSize) -> [CGRect] {
    let total = weights.reduce(0) { $0 + max($1, 0) }
    guard total > 0, size.width > 0, size.height > 0 else { return weights.map { _ in .zero } }
    let scale = Double(size.width * size.height) / total
    let order = weights.indices.sorted { weights[$0] > weights[$1] }
    var rects = Array(repeating: CGRect.zero, count: weights.count)
    var free = CGRect(origin: .zero, size: size)
    var row: [Int] = []
    for index in order where weights[index] > 0 {
      let side = Double(min(free.width, free.height))
      let areas = { (members: [Int]) in members.map { max(weights[$0], 0) * scale } }
      if row.isEmpty || worst(areas(row + [index]), side: side) <= worst(areas(row), side: side) {
        row.append(index)
      } else {
        free = place(row, areas: areas(row), in: free, into: &rects)
        row = [index]
      }
    }
    if !row.isEmpty { _ = place(row, areas: row.map { max(weights[$0], 0) * scale }, in: free, into: &rects) }
    return rects
  }

  private static func worst(_ areas: [Double], side: Double) -> Double {
    let sum = areas.reduce(0, +)
    guard let largest = areas.max(), let smallest = areas.min(), sum > 0, smallest > 0 else { return .infinity }
    return max(side * side * largest / (sum * sum), sum * sum / (side * side * smallest))
  }

  /// Lays the row along the shorter side of `free`, and returns what is left.
  private static func place(_ row: [Int], areas: [Double], in free: CGRect, into rects: inout [CGRect]) -> CGRect {
    let sum = areas.reduce(0, +)
    if free.width >= free.height {
      let width = CGFloat(sum) / free.height
      var y = free.minY
      for (index, area) in zip(row, areas) {
        let height = CGFloat(area) / width
        rects[index] = CGRect(x: free.minX, y: y, width: width, height: height)
        y += height
      }
      return CGRect(x: free.minX + width, y: free.minY, width: free.width - width, height: free.height)
    } else {
      let height = CGFloat(sum) / free.width
      var x = free.minX
      for (index, area) in zip(row, areas) {
        let width = CGFloat(area) / height
        rects[index] = CGRect(x: x, y: free.minY, width: width, height: height)
        x += width
      }
      return CGRect(x: free.minX, y: free.minY + height, width: free.width, height: free.height - height)
    }
  }
}
