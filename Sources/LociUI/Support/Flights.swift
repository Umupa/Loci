import AppKit
import LociModel
import SwiftUI

/// A place in the window a picture can fly from or land on.
enum FlightMark: Hashable {
  /// A follow's picture in the row above the gallery.
  case follow(EntityID)
  /// A follow's picture at the top of its page.
  case followHead(EntityID)
  /// An episode's picture on a follow page.
  case episode(EpisodeKey)
  /// The picture on the follow card under the link field.
  case followCard
  /// A library category in the sidebar.
  case category(LibraryCategory)
  /// The link field at the top of a library page, which the follow card hangs under.
  case linkField
}

/// Pictures on their way from one place in the window to another, across pages: a follow's picture growing
/// into its page and back, a new follow landing in the row, an episode taken in falling into its category. The
/// place a picture lands on keeps its own picture hidden until it arrives. With reduced motion nothing flies.
@MainActor
@Observable
final class Flights {
  struct Flight: Identifiable, Equatable {
    let id = UUID()
    let picture: NSImage?
    let from: CGRect
    let to: FlightMark
    /// The corner radius as a share of the shorter side, where it starts and where it lands.
    let rounding: (from: CGFloat, to: CGFloat)
    /// How far the path bows upward.
    let arc: CGFloat

    static func == (one: Flight, other: Flight) -> Bool { one.id == other.id }
  }

  private(set) var flights: [Flight] = []
  /// The category that just took something in, glowing for a moment.
  private(set) var glowing: LibraryCategory?
  @ObservationIgnored private var marks: [FlightMark: CGRect] = [:]
  @ObservationIgnored var reduceMotion = false

  func mark(_ mark: FlightMark, at frame: CGRect) {
    marks[mark] = frame
  }

  func unmark(_ mark: FlightMark, at frame: CGRect) {
    if marks[mark] == frame { marks[mark] = nil }
  }

  func frame(of mark: FlightMark) -> CGRect? { marks[mark] }

  /// Whether a picture is on its way to `mark`, which keeps its own hidden meanwhile.
  func isLanding(on mark: FlightMark) -> Bool {
    flights.contains { $0.to == mark }
  }

  /// Sends `picture` from where `from` is now to `to`, once `to` is on screen.
  func launch(
    _ picture: NSImage?, from: FlightMark, to: FlightMark, rounding: (from: CGFloat, to: CGFloat), arc: CGFloat = 0
  ) {
    guard !reduceMotion, let start = marks[from] else { return }
    flights.append(Flight(picture: picture, from: start, to: to, rounding: rounding, arc: arc))
  }

  func landed(_ flight: Flight) {
    flights.removeAll { $0 == flight }
    if case .category(let category) = flight.to { glowing = category }
  }

  func settled(_ category: LibraryCategory) {
    if glowing == category { glowing = nil }
  }
}

extension EnvironmentValues {
  /// Set by the window; without it nothing flies.
  @Entry var flights: Flights?
}

extension View {
  /// Tells the window's flights where this is.
  func flightMark(_ mark: FlightMark) -> some View {
    modifier(FlightMarking(mark: mark))
  }
}

private struct FlightMarking: ViewModifier {
  @Environment(\.flights) private var flights
  let mark: FlightMark
  @State private var frame: CGRect?

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .global)
      } action: { frame in
        self.frame = frame
        flights?.mark(mark, at: frame)
      }
      .onDisappear { if let frame { flights?.unmark(mark, at: frame) } }
  }
}

/// Draws the flights over the whole window.
struct FlightLayer: View {
  @Environment(\.flights) private var flights
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      let origin = proxy.frame(in: .global).origin
      ZStack(alignment: .topLeading) {
        ForEach(flights?.flights ?? []) { flight in
          FlightView(flight: flight, origin: origin)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .allowsHitTesting(false)
    .onChange(of: reduceMotion, initial: true) { flights?.reduceMotion = reduceMotion }
  }
}

/// One picture on its way: it waits, unseen, for the place it lands on to be laid out, then goes there.
private struct FlightView: View {
  @Environment(\.flights) private var flights
  let flight: Flights.Flight
  let origin: CGPoint
  @State private var landing: CGRect?
  @State private var arrived = false
  @State private var midway = false

  var body: some View {
    let frame = arrived ? (landing ?? flight.from) : flight.from
    let rounding = arrived ? flight.rounding.to : flight.rounding.from
    picture
      .frame(width: frame.width, height: frame.height)
      .clipShape(
        RoundedRectangle(
          cornerRadius: min(frame.width, frame.height) * rounding, style: rounding >= 0.5 ? .circular : .continuous)
      )
      .shadow(color: Palette.warmShadow.opacity(0.22), radius: 14, y: 8)
      .offset(y: midway ? -flight.arc : 0)
      .position(x: frame.midX - origin.x, y: frame.midY - origin.y)
      .opacity(landing == nil ? 0 : 1)
      .task { await fly() }
  }

  @ViewBuilder private var picture: some View {
    if let image = flight.picture {
      Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
    } else {
      Palette.coverPlaceholder
    }
  }

  private func fly() async {
    for _ in 0..<40 {
      if let target = flights?.frame(of: flight.to) {
        landing = target
        break
      }
      try? await Task.sleep(for: .milliseconds(15))
    }
    guard landing != nil else {
      flights?.landed(flight)
      return
    }
    let duration = flight.arc > 0 ? 0.62 : 0.5
    if flight.arc > 0 {
      withAnimation(.easeOut(duration: duration / 2)) {
        midway = true
      } completion: {
        withAnimation(.easeIn(duration: duration / 2)) { midway = false }
      }
    }
    withAnimation(.timingCurve(0.2, 0.9, 0.25, 1.04, duration: duration)) {
      arrived = true
    } completion: {
      flights?.landed(flight)
    }
  }
}
