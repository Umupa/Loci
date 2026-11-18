import Foundation

/// The proxy set in System Settings, for programs that do not read it themselves.
public enum SystemProxy {
  /// `http://host:port` for an HTTPS or HTTP proxy, `socks5://host:port` for SOCKS; `nil` when none is on.
  public static func current() -> String? {
    guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else { return nil }
    return from(settings)
  }

  static func from(_ settings: [String: Any]) -> String? {
    for (enable, host, port, scheme) in [
      ("HTTPSEnable", "HTTPSProxy", "HTTPSPort", "http"), ("HTTPEnable", "HTTPProxy", "HTTPPort", "http"),
      ("SOCKSEnable", "SOCKSProxy", "SOCKSPort", "socks5"),
    ] {
      guard (settings[enable] as? Int) == 1, let name = settings[host] as? String, !name.isEmpty else { continue }
      let number = settings[port] as? Int
      return "\(scheme)://\(name)" + (number.map { ":\($0)" } ?? "")
    }
    return nil
  }
}
