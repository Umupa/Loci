import LociModel

/// The protocol and launch differences between the two Pi-family programs.
enum PiVariant: Sendable {
  case pi
  case bundled
  case omp

  var provider: Provider {
    switch self {
    case .pi: .pi
    case .bundled: .bundledPi
    case .omp: .omp
    }
  }

  var resumeFlag: String {
    switch self {
    case .pi, .bundled: "--session"
    case .omp: "--resume"
    }
  }

  var launchArguments: [String] {
    switch self {
    case .pi, .bundled: ["--mode", "rpc"] + scopeArguments
    case .omp: ["--mode", "rpc", "--approval-mode", "yolo"]
    }
  }

  var scopeArguments: [String] {
    switch self {
    case .bundled: ["--no-extensions", "--no-mcp", "--no-skills", "--no-prompt-templates", "--no-approve"]
    case .pi, .omp: []
    }
  }

  func sessionIsMissing(_ diagnostics: String) -> Bool {
    switch self {
    case .pi, .bundled: diagnostics.contains("No session found")
    case .omp: diagnostics.contains("Error: Session ") && diagnostics.contains("not found.")
    }
  }
}
