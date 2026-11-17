import SwiftUI

/// The content of a Loci window.
public struct RootView: View {
  public init() {}

  public var body: some View {
    Text("Loci")
      .font(.largeTitle)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
