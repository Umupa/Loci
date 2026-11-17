import LociModel

/// The protocol and launch differences between the two Pi-family programs.
enum PiVariant: Sendable {
  case pi
  case omp

  var provider: Mentor.Provider {
    switch self {
    case .pi: .pi
    case .omp: .omp
    }
  }

  var resumeFlag: String {
    switch self {
    case .pi: "--session"
    case .omp: "--resume"
    }
  }

  var launchArguments: [String] {
    switch self {
    case .pi: ["--mode", "rpc"]
    case .omp: ["--mode", "rpc", "--approval-mode", "yolo"]
    }
  }

  func sessionIsMissing(_ diagnostics: String) -> Bool {
    switch self {
    case .pi: diagnostics.contains("No session found")
    case .omp: diagnostics.contains("Error: Session ") && diagnostics.contains("not found.")
    }
  }
}
