import AppKit
import LociModel
import SwiftUI

/// How the app looks, which languages it and the lessons use, and where its data is.
struct GeneralSettingsPage: View {
  @Environment(\.host) private var host
  @AppStorage(AppearanceChoice.key) private var appearance = AppearanceChoice.auto
  @AppStorage(ReadingWidth.key) private var readingWidth = ReadingWidth.comfortable
  @State private var interface = InterfaceLanguage.current
  @State private var lessons: LessonLanguage?
  @State private var folder: HostPath?
  @State private var revealable: LocalFile?

  var body: some View {
    SettingsPage(symbol: Symbols.settings, title: .loci("settings.general")) {
      SettingsGroup(title: .loci("settings.appearance")) {
        HStack(spacing: 18) {
          ForEach(AppearanceChoice.allCases, id: \.self) { choice in
            AppearanceThumbnail(choice: choice, selected: appearance == choice) { appearance = choice }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      SettingsGroup(title: .loci("settings.reading")) {
        SettingsRow {
          Text(.loci("settings.readingWidth"))
        } trailing: {
          PopupPicker(selection: $readingWidth, options: ReadingWidth.allCases.map { ($0, Text($0.name)) })
        }
      }
      SettingsGroup(title: .loci("settings.language")) {
        SettingsRow {
          Text(.loci("settings.interface"))
        } trailing: {
          PopupPicker(selection: $interface, options: InterfaceLanguage.allCases.map { ($0, Text($0.name)) })
        }
        SettingsRow {
          Text(.loci("settings.lessons"))
        } trailing: {
          if let lessons {
            PopupPicker(
              selection: lessonBinding(lessons),
              options: LessonLanguages.offered(keeping: lessons).map { ($0, Text(LessonLanguages.name($0))) }
            )
            .changesData()
          }
        }
      }
      SettingsGroup(title: .loci("settings.data")) {
        SettingsRow {
          Text(
            verbatim: folder.map { NSString(string: $0.text).abbreviatingWithTildeInPath } ?? ""
          )
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
        } trailing: {
          Button {
            if let revealable { NSWorkspace.shared.activateFileViewerSelecting([revealable.url]) }
          } label: {
            Text(.loci("settings.reveal"))
          }
          .buttonStyle(PushStyle())
          .disabled(revealable == nil)
        }
      }
    }
    .onChange(of: interface) { interface.apply() }
    .task {
      lessons = try? await host.run(ReadLessonLanguage())
      folder = try? await host.run(DataLocation())
      revealable = await host.localFile(.dataFolder)
    }
  }

  private func lessonBinding(_ current: LessonLanguage) -> Binding<LessonLanguage> {
    Binding {
      current
    } set: { language in
      lessons = language
      Task { _ = try? await host.run(SetLessonLanguage(language)) }
    }
  }
}

/// A little window in each appearance, the chosen one ringed in amber.
private struct AppearanceThumbnail: View {
  let choice: AppearanceChoice
  let selected: Bool
  let choose: () -> Void

  var body: some View {
    Button(action: choose) {
      VStack(spacing: 7) {
        preview
          .frame(width: 84, height: 56)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(selected ? Palette.accent : Palette.lineStrong, lineWidth: selected ? 3 : Size.hairline)
              .padding(selected ? -3 : 0)
          }
          .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
        Text(choice.name)
          .font(.system(size: 12, weight: selected ? .semibold : .regular))
          .foregroundStyle(selected ? Palette.ink : Palette.inkMuted)
      }
    }
    .buttonStyle(PressStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  @ViewBuilder private var preview: some View {
    switch choice {
    case .light: Window(dark: false)
    case .dark: Window(dark: true)
    case .auto:
      Window(dark: false).overlay {
        Window(dark: true).mask {
          GeometryReader { proxy in
            Path { path in
              path.move(to: CGPoint(x: proxy.size.width * 0.62, y: 0))
              path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
              path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
              path.addLine(to: CGPoint(x: proxy.size.width * 0.38, y: proxy.size.height))
            }
          }
        }
      }
    }
  }

  private struct Window: View {
    let dark: Bool

    var body: some View {
      HStack(spacing: 0) {
        Rectangle().fill(tone(dark ? 0x26221E : 0xEDE7DD)).frame(width: 26)
        VStack(alignment: .leading, spacing: 4) {
          Capsule().fill(tone(dark ? 0xEBA53A : 0xD98E1F)).frame(width: 30, height: 3)
          Capsule().fill(tone(dark ? 0x3A352F : 0xD9D2C6)).frame(height: 3)
          Capsule().fill(tone(dark ? 0x3A352F : 0xD9D2C6)).frame(height: 3)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tone(dark ? 0x121110 : 0xFCFBF8))
      }
    }

    private func tone(_ rgb: UInt32) -> Color { Color(nsColor: NSColor(rgb: rgb)) }
  }
}

/// The language the interface is shown in: the system's, or one Loci is translated into. Takes effect the
/// next time Loci opens.
enum InterfaceLanguage: String, CaseIterable {
  case system
  case chinese = "zh-Hans"
  case english = "en"

  static let key = "AppleLanguages"

  static var current: InterfaceLanguage {
    let chosen = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
    let first = (chosen?[key] as? [String])?.first
    return allCases.first { $0.rawValue == first } ?? .system
  }

  var name: LocalizedStringResource {
    switch self {
    case .system: .loci("language.system")
    case .chinese: "简体中文"
    case .english: "English"
    }
  }

  func apply() {
    if self == .system {
      UserDefaults.standard.removeObject(forKey: Self.key)
    } else {
      UserDefaults.standard.set([rawValue], forKey: Self.key)
    }
  }
}

/// The languages lessons can be written in.
enum LessonLanguages {
  static func offered(keeping current: LessonLanguage) -> [LessonLanguage] {
    let offered: [LessonLanguage] = [.learners, .fixed("zh-Hans"), .fixed("en")]
    return offered.contains(current) ? offered : offered + [current]
  }

  static func name(_ language: LessonLanguage) -> LocalizedStringResource {
    switch language {
    case .learners: .loci("language.learners")
    case .fixed("zh-Hans"): "简体中文"
    case .fixed("en"): "English"
    case .fixed(let tag): LocalizedStringResource(stringLiteral: tag)
    }
  }
}
