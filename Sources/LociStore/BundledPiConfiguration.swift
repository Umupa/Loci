import Foundation
import LociModel

/// What the bundled Pi is started with for one model service: its folder, the model to ask for, and the
/// environment variable that carries the key.
public struct PiConfiguration: Sendable {
  public let directory: URL
  /// `provider/model` as Pi names it.
  public let model: String
  public let keyVariable: String
}

extension Support {
  /// Pi's own providers for a preset at its own address; anything else is a provider of Loci's in `models.json`.
  public func preparePiConfiguration(for service: ModelService) throws -> PiConfiguration {
    let builtIn = Self.builtIn(service)
    let key = TranslationCacheKey([
      service.provider.rawValue, service.api.rawValue, service.address.url.absoluteString, service.model,
    ])
    let directory = root.appending(path: "bundled-pi", directoryHint: .isDirectory)
      .appending(path: key.digest, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

    let shell = directory.appending(path: "loci-shell")
    let variables = (Self.builtInVariables.values.sorted() + [Self.ownVariable]).joined(separator: " ")
    let wrapper = """
      #!/bin/sh
      unset \(variables)
      exec /bin/bash "$@"

      """
    try Data(wrapper.utf8).write(to: shell, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shell.path(percentEncoded: false))

    let settings: [String: String] = ["shellPath": shell.path(percentEncoded: false)]
    try Formats.document(settings).write(to: directory.appending(path: "settings.json"), options: .atomic)
    if let builtIn {
      return PiConfiguration(
        directory: directory, model: builtIn.name + "/" + service.model, keyVariable: builtIn.variable)
    }
    let provider = OwnProvider(
      baseUrl: Self.piBase(service).absoluteString,
      api: service.api == .anthropic ? "anthropic-messages" : "openai-completions",
      authHeader: service.api == .openAI, models: [.init(id: service.model)])
    let models = Providers(providers: [Self.ownProvider: provider])
    try Formats.document(models).write(to: directory.appending(path: "models.json"), options: .atomic)
    return PiConfiguration(
      directory: directory, model: Self.ownProvider + "/" + service.model, keyVariable: Self.ownVariable)
  }

  private static let ownProvider = "loci-model"
  private static let ownVariable = "LOCI_MODEL_API_KEY"
  private static let builtInVariables: [ModelPreset: String] = [
    .openAI: "OPENAI_API_KEY", .anthropic: "ANTHROPIC_API_KEY", .openRouter: "OPENROUTER_API_KEY",
    .deepSeek: "DEEPSEEK_API_KEY",
  ]
  private static let builtInNames: [ModelPreset: String] = [
    .openAI: "openai", .anthropic: "anthropic", .openRouter: "openrouter", .deepSeek: "deepseek",
  ]

  private static func builtIn(_ service: ModelService) -> (name: String, variable: String)? {
    guard let name = builtInNames[service.preset], let variable = builtInVariables[service.preset],
      service.address == service.preset.address, service.api == service.preset.api
    else { return nil }
    return (name, variable)
  }

  /// Pi's Anthropic client adds `/v1` itself.
  private static func piBase(_ service: ModelService) -> URL {
    let url = service.address.url
    guard service.api == .anthropic, url.path().split(separator: "/").last == "v1" else { return url }
    return url.deletingLastPathComponent()
  }

  private struct Providers: Encodable {
    let providers: [String: OwnProvider]
  }

  private struct OwnProvider: Encodable {
    struct Model: Encodable { let id: String }
    let baseUrl: String
    let api: String
    let apiKey = "${LOCI_MODEL_API_KEY}"
    let authHeader: Bool
    let models: [Model]
  }
}
