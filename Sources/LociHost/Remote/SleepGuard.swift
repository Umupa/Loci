import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac from sleeping on its own while another Mac may want to open it.
public protocol SleepGuard: Sendable {
  func keepAwake(_ awake: Bool) async
}

/// A power assertion that prevents idle system sleep. macOS honours this kind of assertion only on AC
/// power, so a laptop on battery still sleeps, and closing the lid always does.
public actor PowerAssertion: SleepGuard {
  private var assertion: IOPMAssertionID?

  public init() {}

  public func keepAwake(_ awake: Bool) {
    if awake, assertion == nil {
      var id = IOPMAssertionID(0)
      let status = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
        "Loci: paired Macs can open this one" as CFString, &id)
      if status == kIOReturnSuccess { assertion = id }
    } else if !awake, let id = assertion {
      IOPMAssertionRelease(id)
      assertion = nil
    }
  }
}
