/// The module map. This table is the architecture: a module may import only
/// what its row lists, and a module that is not in the table may not exist.
///
/// Change a row in the same pull request as the code that needs it, and say
/// why in the description. See `docs/architecture.md`.
enum Architecture {
  struct Module {
    let uses: Set<String>
    let frameworks: Set<String>
    /// Third-party packages. Each one was approved before it was added; ask before adding another.
    let packages: Set<String>
    let isExecutable: Bool

    init(uses: Set<String>, frameworks: Set<String>, packages: Set<String> = [], isExecutable: Bool = false) {
      self.uses = uses
      self.frameworks = frameworks
      self.packages = packages
      self.isExecutable = isExecutable
    }
  }

  static let modules: [String: Module] = [
    "LociModel": Module(uses: [], frameworks: ["Foundation"]),
    "LociStore": Module(
      uses: ["LociModel"], frameworks: ["Foundation", "CoreServices", "Synchronization", "os"],
      packages: ["Yams", "GRDB"]),
    "LociAgents": Module(uses: ["LociModel"], frameworks: ["Foundation", "os"]),
    "LociMedia": Module(
      uses: ["LociModel"],
      frameworks: [
        "Foundation", "AVFoundation", "CoreMedia", "CoreGraphics", "NaturalLanguage", "WebKit", "Synchronization", "os",
      ],
      packages: ["whisper"]),
    "LociCode": Module(uses: ["LociModel"], frameworks: ["Foundation", "os"]),
    "LociRemote": Module(uses: ["LociModel"], frameworks: ["Foundation", "CryptoKit", "Network", "os"]),
    "LociHost": Module(
      uses: ["LociModel", "LociStore", "LociAgents", "LociMedia", "LociCode", "LociRemote"],
      frameworks: ["Foundation", "os"]),
    "LociUI": Module(
      uses: ["LociModel"],
      frameworks: [
        "Foundation", "Observation", "SwiftUI", "AppKit", "PDFKit", "AVKit", "UniformTypeIdentifiers", "os",
      ],
      packages: ["Markdown", "Textual", "HighlightSwift", "SwiftMath"]),
    "LociEval": Module(
      uses: ["LociModel", "LociHost", "LociAgents"], frameworks: ["Foundation"], isExecutable: true),
    "Loci": Module(
      uses: ["LociModel", "LociUI", "LociHost"], frameworks: ["Foundation", "SwiftUI", "os"], isExecutable: true),
  ]

  /// Constructs that only some modules may use, because each one is a way out
  /// of the process or onto the disk that should have a single owner.
  static let restricted: [Restriction] = [
    Restriction(
      pattern: #"\bProcess\("#, allowedIn: ["LociAgents", "LociMedia"],
      fix: "Only LociAgents and LociMedia start other programs. Ask for the result through the Host instead."),
    Restriction(
      pattern: #"\bFileManager\b"#, allowedIn: ["LociStore", "LociEval"],
      fix: "Only LociStore touches the disk. Add what you need to the store and call that."),
    Restriction(
      pattern: #"\bURLSession\b"#, allowedIn: ["LociMedia", "LociRemote"],
      fix: "Only LociMedia (fetching) and LociRemote (the channel) use the network."),
    Restriction(
      pattern: #"\bUserDefaults\b"#, allowedIn: ["LociUI"],
      fix: "Preferences that matter belong in LociStore. UserDefaults is for per-window conveniences in LociUI."),
  ]

  /// Constructs that are wrong everywhere. Each message says what to do instead.
  static let forbidden: [Restriction] = [
    Restriction(
      pattern: #"\btry!"#,
      fix: "Propagate the error with `throws`, or handle it. A crash here loses what the reader was doing."),
    Restriction(
      pattern: #"\bas!"#,
      fix: "Model the cases with an enum or a protocol so the cast is not needed, or use `as?` and handle nil."),
    Restriction(
      pattern: #"\b(fatalError|preconditionFailure)\("#,
      fix: "Make the impossible state unrepresentable in the type, or throw an error the caller can show."),
    Restriction(
      pattern: #"\b(print|debugPrint|NSLog)\("#,
      fix: "Use `os.Logger` for diagnostics. If the user should see it, it belongs in the interface."),
    Restriction(
      pattern: #"@unchecked\s+Sendable|nonisolated\(unsafe\)|@preconcurrency"#,
      fix: "Fix the isolation: make it an actor, a value type, or keep it on one actor. Do not silence the checker."),
    Restriction(
      pattern: #"\b(DispatchSemaphore|DispatchGroup|NSLock|OperationQueue)\b|Thread\.sleep|Task\.detached"#,
      fix: "Use structured concurrency: async functions, task groups, actors, `Mutex`, `Task.sleep`."),
    Restriction(
      pattern: #"\bDispatchQueue\b"#, allowedFiles: ["Sources/LociStore/FileEvents.swift"],
      fix: "Use structured concurrency. GCD appears only where a system API delivers callbacks on a queue "
        + "(FSEvents in Sources/LociStore/FileEvents.swift), and the callback goes straight into an AsyncStream."),
    Restriction(
      pattern: #"swift-format-ignore"#,
      fix:
        "Change the code so the formatter accepts it. If the rule is wrong for the whole project, change `.swift-format`."
    ),
  ]

  struct Restriction {
    let pattern: String
    let allowedIn: Set<String>
    /// Single files allowed to use the construct, for a narrow bridge to a system API.
    let allowedFiles: Set<String>
    let fix: String

    init(pattern: String, allowedIn: Set<String> = [], allowedFiles: Set<String> = [], fix: String) {
      self.pattern = pattern
      self.allowedIn = allowedIn
      self.allowedFiles = allowedFiles
      self.fix = fix
    }
  }

  static let longestSourceFile = 400
}
