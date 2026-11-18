import Foundation
import LociModel
import Testing

@testable import LociRemote

struct FrameTests {
  @Test func everyFrameRoundTrips() {
    let bytes = Data((0..<300).map { UInt8($0 % 256) })
    let frames: [Frame] = [
      .call(id: 1, name: "mentor.create", body: Data("{}".utf8)),
      .reply(id: 2, body: bytes),
      .failure(id: 3, .notFound("mentor")),
      .cancel(id: 4),
      .subscribe(id: 5, name: "conversation", body: Data("{\"mentor\":1}".utf8)),
      .feed(id: 6, body: bytes),
      .delta(id: 7, body: Data()),
      .unsubscribe(id: .max),
      .resend(id: 8),
      .uploadPart(id: 9, bytes: bytes),
      .uploadEnd(id: 10, fileName: "调度 talk.mov"),
      .unpaired,
    ]

    for frame in frames {
      #expect(Frame(frame.encoded) == frame)
    }
  }

  @Test func aTruncatedFrameIsRejected() {
    let frame = Frame.call(id: 1, name: "mentor.create", body: Data()).encoded

    #expect(Frame(frame.prefix(8)) == nil)
    #expect(Frame(Data([99, 0, 0, 0, 1])) == nil)
  }
}
