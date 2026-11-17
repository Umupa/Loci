import Foundation

extension PiDriver {
  /// omp through the shared Pi-family RPC transport.
  public static func omp(
    executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) -> PiDriver {
    PiDriver(
      variant: .omp, executable: executable, arguments: arguments, environment: environment, launcher: launcher,
      clock: clock)
  }
}
