import Synchronization
import Testing

@testable import LociConnect

/// NX-S6: once macOS let the app write, it may undo what it wrote for as long as the app runs, even when macOS
/// goes on saying it was never asked, as it does for an app signed only for this Mac.
struct WriteAccessTests {
  /// macOS as it treats such an app: it says yes when asked, without asking the person, and still says it was
  /// never asked.
  final class Forgetful: Sendable {
    let asked = Mutex(0)

    var access: WriteAccess {
      WriteAccess(
        status: { _ in .undetermined },
        request: { _ in
          self.asked.withLock { $0 += 1 }
          return true
        })
    }
  }

  @Test func whatWasAllowedOnceStaysAllowedWithoutAskingAgain() async {
    let macOS = Forgetful()
    let access = macOS.access

    #expect(await !access.isAllowed(.events))
    #expect(await access.allow(.events))
    #expect(await access.isAllowed(.events))
    #expect(await access.allow(.events))
    #expect(macOS.asked.withLock { $0 } == 1)
    #expect(await !access.isAllowed(.reminders))
  }

  @Test func whatMacOSSaysIsGrantedIsAllowedWithoutAsking() async {
    let access = WriteAccess(status: { _ in .granted }, request: { _ in false })

    #expect(await access.isAllowed(.reminders))
    #expect(await access.allow(.reminders))
  }

  @Test func whatThePersonDeniedIsNotAskedAgainNorAllowed() async {
    let asked = Mutex(0)
    let access = WriteAccess(
      status: { _ in .denied },
      request: { _ in
        asked.withLock { $0 += 1 }
        return true
      })

    #expect(await !access.allow(.events))
    #expect(await !access.isAllowed(.events))
    #expect(asked.withLock { $0 } == 0)
  }
}
