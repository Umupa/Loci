import LociModel
import SwiftUI

/// The answers Loci offers under its latest reply, on the person's side: one click sends it as theirs.
struct QuickReplyChips: View {
  let replies: [String]
  var size: CGFloat = 15
  let send: (String) -> Void
  @Environment(\.openPlace) private var openPlace

  var body: some View {
    HStack(spacing: 8) {
      ForEach(replies, id: \.self) { reply in
        let answer = QuickAnswer(reply)
        Button {
          switch answer.place {
          case let place?: openPlace(place)
          case nil: send(reply)
          }
        } label: {
          Text(verbatim: answer.words).font(.system(size: size)).lineLimit(1)
        }
        .buttonStyle(QuickReplyStyle())
      }
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
  }
}

/// One answer Loci offers: words the person says, or, written `[words](loci://connectors/<id>)`, a place in
/// the app the answer opens, such as a connector to connect again.
struct QuickAnswer: Equatable {
  let words: String
  let place: Place?

  init(_ reply: String) {
    if let link = reply.wholeMatch(of: /\[([^\]]+)\]\(loci:\/\/connectors\/([A-Za-z0-9._-]+)\)/) {
      words = String(link.1)
      place = .connector(ConnectorID(String(link.2)))
    } else {
      words = reply
      place = nil
    }
  }
}

private struct QuickReplyStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    Chip(configuration: configuration)
  }

  private struct Chip: View {
    let configuration: Configuration
    @State private var hovering = false
    @Environment(\.reducesMotion) private var reduceMotion

    var body: some View {
      configuration.label
        .foregroundStyle(Palette.ink)
        .padding(.vertical, 13)
        .padding(.horizontal, 18)
        .background(Capsule(style: .circular).fill(hovering ? Palette.fill : .clear))
        .overlay(Capsule(style: .circular).strokeBorder(Palette.ink.opacity(0.18), lineWidth: Size.hairline))
        .contentShape(Capsule(style: .circular))
        .scaleEffect(configuration.isPressed ? 0.96 : 1)
        .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
        .onHover { hovering = $0 }
    }
  }
}
