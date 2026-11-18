import Foundation

/// The script run in every page of the built-in browser. It reports, after the page loads and again whenever
/// it changes, the single videos linked from it and whether it holds a readable body of text.
enum PageScript {
  static let channel = "loci"

  /// Reads a report the script sent.
  static func facts(from body: Any) -> PageFacts? {
    guard let report = body as? [String: Any] else { return nil }
    let videos = (report["videos"] as? [[String: Any]] ?? []).compactMap { video -> FoundVideo? in
      guard let address = video["url"] as? String, let url = URL(string: address),
        let title = (video["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
      else { return nil }
      let duration = (video["duration"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      return FoundVideo(
        url: url, title: title, thumbnail: (video["thumbnail"] as? String).flatMap(URL.init(string:)),
        duration: duration?.isEmpty == false ? duration : nil)
    }
    return PageFacts(videos: videos, hasArticle: report["article"] as? Bool ?? false)
  }

  /// Text this long or longer in one block reads as an article; Chinese and Japanese say more per character.
  static let source = #"""
    (() => {
      if (window.__lociWatching) return;
      window.__lociWatching = true;
      const watch = (u) => {
        const host = u.hostname.replace(/^www\.|^m\./, '');
        if (host.endsWith('youtube.com') && u.pathname === '/watch' && u.searchParams.get('v'))
          return 'https://www.youtube.com/watch?v=' + u.searchParams.get('v');
        if (host === 'youtu.be' && u.pathname.length > 1) return 'https://www.youtube.com/watch?v=' + u.pathname.slice(1);
        const bili = u.pathname.match(/^\/video\/[A-Za-z0-9]+/);
        if (host.endsWith('bilibili.com') && bili) return 'https://www.bilibili.com' + bili[0];
        return null;
      };
      const textOf = (el) => (el && el.textContent || '').replace(/\s+/g, ' ').trim();
      const report = () => {
        const here = watch(new URL(location.href));
        const found = new Map();
        for (const a of document.querySelectorAll('a[href]')) {
          let u; try { u = new URL(a.href, location.href); } catch { continue; }
          const key = watch(u);
          if (!key || key === here) continue;
          const v = found.get(key) || { url: key };
          const named = a.getAttribute('title') || a.getAttribute('aria-label') || textOf(a.querySelector('#video-title, h3, .title'));
          const written = a.querySelector('img') ? '' : textOf(a);
          if (named && named.length < 300 && !v.named) { v.title = named; v.named = true; }
          if (!v.title && written && written.length < 300) v.title = written;
          const img = a.querySelector('img');
          if (!v.thumbnail && img && img.src && img.src.startsWith('http')) v.thumbnail = img.src;
          const time = textOf(a.querySelector('.badge-shape-wiz__text, ytd-thumbnail-overlay-time-status-renderer, .bili-video-card__stats__duration, .duration'));
          if (!v.duration && /^\d{1,2}(:\d{2}){1,2}$/.test(time)) v.duration = time;
          found.set(key, v);
          if (found.size >= 60) break;
        }
        const blocks = [...document.querySelectorAll('article, main, [role=main], .post-content, .entry-content, #content')];
        const longest = Math.max(0, ...blocks.map((b) => [...b.querySelectorAll('p')].map(textOf).join('').length));
        const cjk = /[぀-ヿ㐀-鿿]/.test(document.title + textOf(document.querySelector('p')));
        window.webkit.messageHandlers.loci.postMessage({
          videos: [...found.values()].filter((v) => v.title),
          article: longest >= (cjk ? 500 : 1500),
        });
      };
      let pending = null;
      const soon = () => { clearTimeout(pending); pending = setTimeout(report, 600); };
      new MutationObserver(soon).observe(document.documentElement, { childList: true, subtree: true });
      for (const name of ['pushState', 'replaceState']) {
        const original = history[name];
        history[name] = function () { const r = original.apply(this, arguments); soon(); return r; };
      }
      addEventListener('popstate', soon);
      report();
    })();
    """#
}
