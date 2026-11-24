import Foundation
import Testing

@testable import LociMedia

/// CN-S11: a website read with the person's sign-in sends only GET, and the app knows which sites are
/// signed in without holding a cookie's value.
struct ReadOnlyPageTests {
  @Test func onlyAGetMayNavigate() {
    #expect(ReadOnlyPage.allows(method: "GET"))
    #expect(ReadOnlyPage.allows(method: "get"))
    #expect(ReadOnlyPage.allows(method: nil))
    for method in ["POST", "PUT", "PATCH", "DELETE"] { #expect(!ReadOnlyPage.allows(method: method)) }
  }

  @Test func thePageScriptStandsInFrontOfEveryWayAPageSendsSomething() {
    for guarded in [
      "window.fetch", "XMLHttpRequest.prototype.open", "navigator.sendBeacon", "HTMLFormElement.prototype.submit",
      "\"submit\"",
    ] {
      #expect(ReadOnlyPage.script.contains(guarded))
    }
  }

  @Test func aCookieBelongsToItsSiteAndItsSubdomainsOnly() {
    let cookie = SiteCookie(domain: ".x.com", name: "auth_token", expires: nil)
    #expect(cookie.belongs(to: "x.com"))
    #expect(SiteCookie(domain: "api.x.com", name: "a", expires: nil).belongs(to: "x.com"))
    #expect(!SiteCookie(domain: "notx.com", name: "a", expires: nil).belongs(to: "x.com"))
    #expect(!cookie.belongs(to: "twitter.com"))
  }
}
