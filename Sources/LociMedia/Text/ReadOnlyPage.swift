import Foundation

/// What keeps a page read with the person's sign-in to reading: the page is loaded and asked for its text,
/// and nothing it does may send anything but a GET.
///
/// Three things hold it: the web view only navigates with GET, the script below refuses every other request
/// the page's own scripts make, and the page is closed as soon as its text is taken, never clicked or
/// scrolled. What the script cannot reach (a WebSocket, a service worker) is the risk left.
enum ReadOnlyPage {
  /// Whether a navigation may go ahead: only a GET, or a request that says no method at all.
  static func allows(method: String?) -> Bool {
    (method ?? "GET").uppercased() == "GET"
  }

  /// Added to every frame at document start, in the page's own world so it stands in front of the page's
  /// scripts: `fetch`, `XMLHttpRequest`, `sendBeacon` and form submits that are not GET are refused.
  static let script = """
    (() => {
      const refuse = () => { throw new TypeError("Loci reads this page; it sends only GET."); };
      const isRead = (method) => String(method || "GET").toUpperCase() === "GET";
      const originalFetch = window.fetch;
      window.fetch = function (input, init) {
        const method = (init && init.method) || (input && input.method) || "GET";
        return isRead(method) ? originalFetch.apply(this, arguments) : Promise.reject(new TypeError("Loci reads this page; it sends only GET."));
      };
      const originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method) {
        if (!isRead(method)) refuse();
        return originalOpen.apply(this, arguments);
      };
      if (navigator.sendBeacon) navigator.sendBeacon = () => false;
      const originalSubmit = HTMLFormElement.prototype.submit;
      HTMLFormElement.prototype.submit = function () {
        if (isRead(this.method)) return originalSubmit.apply(this, arguments);
      };
      document.addEventListener("submit", (event) => {
        if (!isRead(event.target && event.target.method)) { event.preventDefault(); event.stopImmediatePropagation(); }
      }, true);
    })();
    """
}
