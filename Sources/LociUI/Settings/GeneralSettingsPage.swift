import AppKit
import LociModel
import SwiftUI

/// How the app looks, which language it speaks, and where its data is.
struct GeneralSettingsPage: View {
  var version = AppVersion(of: .main)
  @Environment(\.openWindow) private var openWindow
  @Environment(\.host) private var host
  @Environment(\.signIns) private var signIns
  @Environment(\.browser) private var browserSession
  @Environment(\.dataReset) private var dataReset
  @AppStorage(AppearanceChoice.key) private var appearance = AppearanceChoice.auto
  @AppStorage(ReadingWidth.key) private var readingWidth = ReadingWidth.comfortable
  @State private var interface = InterfaceLanguage.current
  @State private var folder: HostPath?
  @State private var revealable: LocalFile?
  @State private var signInChoice: SignInChoice?

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
      }
      if let browser = signInBrowser {
        SettingsGroup(title: .loci("sidebar.browser")) {
          SettingsRow {
            Text(.loci("browser.useSignIns \(browser.name)"))
          } trailing: {
            Toggle(isOn: Binding(get: { signInChoice == .using(browser) }, set: { use(browser, $0) })) {
              Text(.loci("browser.useSignIns \(browser.name)"))
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
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
        if let dataReset { ResetRow(reset: dataReset) }
      }
      SettingsGroup(title: nil) {
        SettingsRow {
          Text(.loci("settings.version"))
        } trailing: {
          Text(verbatim: version.text).foregroundStyle(Palette.inkMuted).textSelection(.enabled)
          Button {
            openWindow(id: AppUpdateWindow.id)
          } label: {
            Text(AppUpdateWindow.title)
          }
          .buttonStyle(PushStyle())
        }
      }
    }
    .onChange(of: interface) { interface.apply() }
    .task {
      signInChoice = await signIns?.choice()
      folder = try? await host.run(DataLocation())
      revealable = await host.localFile(.dataFolder)
    }
  }
}

extension GeneralSettingsPage {
  /// The browser whose sign-ins the built-in browser could start with, if there is one.
  private var signInBrowser: SignInBrowser? {
    switch signInChoice {
    case .offer(let browser), .using(let browser), .declined(let browser): browser
    case .unavailable, nil: nil
    }
  }

  private func use(_ browser: SignInBrowser, _ on: Bool) {
    guard let signIns, let browserSession else { return }
    signInChoice = on ? .using(browser) : .declined(browser)
    Task {
      if on {
        await browserSession.acceptSignIns(from: browser)
      } else {
        await browserSession.declineSignIns()
      }
      signInChoice = await signIns.choice()
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

/// Which release this copy of Loci is: the version people talk about, and the build, which only goes up.
struct AppVersion: Equatable {
  let number: String
  let build: String

  init(number: String, build: String) {
    self.number = number
    self.build = build
  }

  init(of bundle: Bundle) {
    number = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
  }

  /// `1.1.0 (412)`.
  var text: String { "\(number) (\(build))" }
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
