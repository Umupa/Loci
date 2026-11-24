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
    "LociModel": Module(uses: [], frameworks: ["Foundation", "CryptoKit"]),
    "LociStore": Module(
      uses: ["LociModel"],
      frameworks: [
        "Foundation", "CommonCrypto", "CoreServices", "CryptoKit", "Darwin", "Security", "Synchronization", "os",
      ],
      packages: ["GRDB"]),
    "LociAgents": Module(uses: ["LociModel"], frameworks: ["Foundation", "os"]),
    "LociMedia": Module(
      uses: ["LociModel"],
      frameworks: [
        "Foundation", "AVFoundation", "CoreMedia", "CoreGraphics", "ImageIO", "PDFKit", "NaturalLanguage", "WebKit",
        "Synchronization", "UniformTypeIdentifiers", "os",
      ],
      packages: ["whisper", "Markdown", "FluidAudio"]),
    "LociCode": Module(uses: ["LociModel"], frameworks: ["Foundation", "os"]),
    "LociRemote": Module(uses: ["LociModel"], frameworks: ["Foundation", "CryptoKit", "Network", "os"]),
    "LociConnect": Module(uses: ["LociModel"], frameworks: ["Foundation", "CryptoKit", "EventKit", "Network", "os"]),
    "LociHost": Module(
      uses: ["LociModel", "LociStore", "LociAgents", "LociMedia", "LociCode", "LociRemote", "LociConnect"],
      frameworks: ["Foundation", "IOKit", "os"]),
    "LociUI": Module(
      uses: ["LociModel"],
      frameworks: [
        "Foundation", "Observation", "SwiftUI", "AppKit", "PDFKit", "AVKit", "AVFoundation", "MediaPlayer",
        "WebKit", "UniformTypeIdentifiers", "ImageIO", "ServiceManagement", "os",
      ],
      packages: ["Markdown", "Textual", "HighlightSwift", "SwiftMath"]),
    "Loci": Module(
      uses: ["LociModel", "LociUI", "LociHost"], frameworks: ["Foundation", "SwiftUI", "os"], isExecutable: true),
    "LociTool": Module(uses: ["LociModel", "LociRemote"], frameworks: ["Foundation"], isExecutable: true),
  ]

  /// Constructs that only some modules may use, because each one is a way out
  /// of the process or onto the disk that should have a single owner.
  static let restricted: [Restriction] = [
    Restriction(
      pattern: #"\bProcess\("#, allowedIn: ["LociAgents", "LociMedia"],
      fix: "Only LociAgents and LociMedia start other programs. Ask for the result through the Host instead."),
    Restriction(
      pattern: #"\bFileManager\b"#, allowedIn: ["LociStore"],
      fix: "Only LociStore touches the disk. Add what you need to the store and call that."),
    Restriction(
      pattern: #"\bURLSession\b"#, allowedIn: ["LociMedia", "LociRemote", "LociConnect"],
      fix: "Only LociMedia (fetching), LociRemote (the channel) and LociConnect (connectors) use the network."),
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
      pattern: #"WKWebsiteDataStore\.default\(\)|(WKWebsiteDataStore|websiteDataStore)\s*=\s*\.default\(\)"#,
      allowedFiles: [
        "Sources/LociMedia/Text/PageReader.swift", "Sources/LociMedia/Network/SiteSignIns.swift",
        "Sources/LociUI/Browser/BrowserSession.swift",
      ],
      fix: "The default WebKit store holds the person's sign-ins. Only the built-in browser shows pages with it "
        + "(Sources/LociUI/Browser/BrowserSession.swift); Loci reads with it only through PageReader's "
        + "`Visitor.signedIn`, which sends only GET (Sources/LociMedia/Text/PageReader.swift); "
        + "Sources/LociMedia/Network/SiteSignIns.swift only looks at which cookies it has. Read a page through "
        + "PageReader instead."),
    Restriction(
      pattern: #"\bDispatchQueue\b"#,
      allowedFiles: ["Sources/LociStore/FileEvents.swift", "Sources/LociUI/Media/RangedMedia.swift"],
      fix: "Use structured concurrency. GCD appears only where a system API delivers callbacks on a queue "
        + "(FSEvents in Sources/LociStore/FileEvents.swift, AVAssetResourceLoader in "
        + "Sources/LociUI/Media/RangedMedia.swift), and the callback goes straight to an AsyncStream or the main actor."
    ),
    Restriction(
      pattern: #"swift-format-ignore"#,
      fix:
        "Change the code so the formatter accepts it. If the rule is wrong for the whole project, change `.swift-format`."
    ),
  ]

  /// SF Symbols the interface never names, found in the string literals of `Sources`. Each message says why and
  /// what to do instead.
  static let forbiddenSymbols: [Restriction] = [
    Restriction(
      pattern: #""[^"]*sparkle[^"]*""#,
      fix: "Sparkles are the stock sign for \"AI did this\" and say nothing about what the control does. Loci never "
        + "uses them. Pick the SF Symbol that names the action itself, or draw a `Shape` for it, as `FoldOthers` does "
        + "for showing only the key points.")
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

  /// Where every `Command` and `Subscription` is listed, so another Mac can call it.
  static let wireRegistry = "Sources/LociModel/Wire.swift"
}
