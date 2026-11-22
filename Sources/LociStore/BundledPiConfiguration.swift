import Foundation
import LociModel

extension Support {
  public func preparePiConfiguration(for service: ModelService) throws -> URL {
    let key = TranslationCacheKey([service.provider.rawValue, service.endpoint.absoluteString, service.model])
    let directory = root.appending(path: "bundled-pi", directoryHint: .isDirectory)
      .appending(path: key.digest, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

    let shell = directory.appending(path: "loci-shell")
    let wrapper = """
      #!/bin/sh
      unset OPENAI_API_KEY ANTHROPIC_API_KEY OPENROUTER_API_KEY DEEPSEEK_API_KEY LOCI_MODEL_API_KEY
      exec /bin/bash "$@"

      """
    try Data(wrapper.utf8).write(to: shell, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shell.path(percentEncoded: false))

    let settings: [String: String] = ["shellPath": shell.path(percentEncoded: false)]
    try Formats.document(settings).write(to: directory.appending(path: "settings.json"), options: .atomic)
    if service.provider == .compatible {
      let provider = CustomProvider(baseUrl: service.baseURL.absoluteString, models: [.init(id: service.model)])
      let models = Providers(providers: ["loci-compatible": provider])
      try Formats.document(models).write(to: directory.appending(path: "models.json"), options: .atomic)
    }
    return directory
  }

  private struct Providers: Encodable {
    let providers: [String: CustomProvider]
  }

  private struct CustomProvider: Encodable {
    struct Model: Encodable { let id: String }
    let baseUrl: String
    let api = "openai-completions"
    let apiKey = "${LOCI_MODEL_API_KEY}"
    let authHeader = true
    let models: [Model]
  }
}
