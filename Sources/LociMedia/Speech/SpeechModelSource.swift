import Foundation
import LociModel

extension SpeechModel {
  /// The ggml file whisper.cpp publishes for this model.
  public var fileName: String {
    switch self {
    case .tiny: "ggml-tiny.bin"
    case .base: "ggml-base.bin"
    case .small: "ggml-small.bin"
    case .medium: "ggml-medium.bin"
    case .largeV3TurboQuantized: "ggml-large-v3-turbo-q5_0.bin"
    case .largeV3Turbo: "ggml-large-v3-turbo.bin"
    case .largeV3: "ggml-large-v3.bin"
    }
  }

  /// Where the file is downloaded from: whisper.cpp's own repository on Hugging Face.
  public var source: URL {
    URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
  }
}
