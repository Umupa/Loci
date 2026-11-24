import Foundation
import Testing

@testable import LociConnect

/// CN-S1: the browser comes back to a port on 127.0.0.1 that only this connection listens at, and waits there
/// for a page saying what came of the sign-in.
@Suite(.timeLimit(.minutes(1)))
struct LoopbackTests {
  private func get(_ url: URL, language: String? = nil) async throws -> (page: String, status: Int) {
    var request = URLRequest(url: url)
    if let language { request.setValue(language, forHTTPHeaderField: "Accept-Language") }
    let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
    return (String(decoding: data, as: UTF8.self), (response as? HTTPURLResponse)?.statusCode ?? 0)
  }

  @Test func theBrowserWaitsForTheSignInAndIsToldItConnectedInItsLanguage() async throws {
    let wait = try await LoopbackReceiver().open(for: "Notion")
    #expect(wait.redirect.host() == "127.0.0.1" && wait.redirect.path() == "/callback")
    let back = try #require(URL(string: wait.redirect.absoluteString + "?code=abc&state=xyz"))

    async let browser = get(back, language: "zh-CN,zh;q=0.9,en;q=0.8")
    let callback = try await wait.callback()
    await wait.answer(.connected)
    let page = try await browser.page
    await wait.close()

    #expect(callback.query() == "code=abc&state=xyz")
    #expect(page.contains("已连上 Notion") && !page.contains("Connected"))
  }

  @Test func aRefusedSignInSaysSoInEnglishWhenTheBrowserAsksForIt() async throws {
    let wait = try await LoopbackReceiver().open(for: "Linear")
    let back = try #require(URL(string: wait.redirect.absoluteString + "?error=access_denied"))

    async let browser = get(back, language: "en-US,en;q=0.9,zh;q=0.5")
    _ = try await wait.callback()
    await wait.answer(.declined)
    let page = try await browser.page
    await wait.close()

    #expect(page.contains("Access to Linear wasn’t granted") && !page.contains("连接"))
  }

  @Test func aBrowserStillWaitingWhenTheSignInIsClosedIsToldItFailed() async throws {
    let wait = try await LoopbackReceiver().open(for: "Sentry")
    let back = try #require(URL(string: wait.redirect.absoluteString + "?code=abc"))

    async let browser = get(back, language: "en")
    _ = try await wait.callback()
    await wait.close()

    #expect(try await browser.page.contains("Couldn’t connect to Sentry"))
  }

  @Test func aRequestWithoutCodeOrErrorIsAnsweredAndIgnored() async throws {
    let wait = try await LoopbackReceiver().open(for: "Notion")
    let favicon = try #require(URL(string: "http://127.0.0.1:\(wait.redirect.port ?? 0)/favicon.ico"))

    #expect(try await get(favicon).status == 404)
    await wait.close()
  }

  @Test func thePageDrawsEverythingItselfOnPaperInLightAndDark() {
    let page = SignInPage(service: "<Notion>", outcome: .failed, language: .chinese).html
    #expect(page.contains("data:image/png;base64,"))
    #expect(!page.contains("http://") && !page.contains("https://"))
    #expect(page.contains("prefers-color-scheme: dark"))
    #expect(page.contains("没能连上 &lt;Notion&gt;"))
    #expect(page.contains("window.close()"))
  }

  @Test(arguments: [
    ("zh-CN,zh;q=0.9,en;q=0.8", SignInPage.Language.chinese), ("en-GB,zh-Hans;q=0.6", .english),
    ("en;q=0.3,zh-TW;q=0.8", .chinese), ("ja-JP,fr", .english), ("", .english),
  ])
  func theLanguageIsTheFirstOfChineseOrEnglishTheBrowserAsksFor(header: String, language: SignInPage.Language) {
    #expect(SignInPage.Language(acceptLanguage: header) == language)
  }
}
