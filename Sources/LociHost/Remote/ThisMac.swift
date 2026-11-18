import Foundation
import IOKit
import LociModel

/// What this Mac is called and what kind it is, as other Macs will list it.
public enum ThisMac {
  /// The computer name from Sharing settings.
  public static var name: String {
    Foundation.Host.current().localizedName ?? "Mac"
  }

  public static var model: MachineModel {
    model(fromProductName: productName ?? "")
  }

  /// From names such as "MacBook Pro (14-inch, M3, Nov 2023)" or "Mac mini (2024)".
  static func model(fromProductName name: String) -> MachineModel {
    let lowered = name.lowercased()
    if lowered.hasPrefix("macbook") { return .laptop }
    if lowered.hasPrefix("mac mini") { return .mini }
    if lowered.hasPrefix("imac") { return .iMac }
    if lowered.hasPrefix("mac studio") { return .studio }
    if lowered.hasPrefix("mac pro") { return .pro }
    return .other
  }

  private static var productName: String? {
    let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
    guard entry != 0 else { return nil }
    defer { IOObjectRelease(entry) }
    guard let value = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)
    else { return nil }
    guard let data = value.takeRetainedValue() as? Data else { return nil }
    return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
  }
}
