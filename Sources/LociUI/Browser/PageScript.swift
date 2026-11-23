import Foundation

/// The script run in every page of the built-in browser. It reports, after the page loads and again whenever
/// it changes, the single videos and the papers linked from it and whether it holds a readable body of text. A video is a
/// link with a title, a thumbnail or a length. Buttons such as a playlist's "Play all" and "Shuffle", and the
/// header of a playlist, link to a video too and are left out; they are told by the shape of the button or the
/// header, never by a class that merely mentions a button, which YouTube's video cards also do.
enum PageScript {
  static let channel = "loci"

  static let article = #"""
    const page = document.documentElement.cloneNode(true);
    page.querySelectorAll('script:not([type="application/ld+json"]), iframe, object, embed, form, input, textarea, select')
      .forEach(node => node.remove());
    return { url: location.href, html: page.outerHTML };
    """#

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
    let papers = (report["papers"] as? [[String: Any]] ?? []).compactMap { paper -> FoundPaper? in
      guard let address = paper["url"] as? String, let url = URL(string: address),
        let title = (paper["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
      else { return nil }
      return FoundPaper(url: url, title: title)
    }
    return PageFacts(videos: videos, papers: papers, hasArticle: report["article"] as? Bool ?? false)
  }

  /// Rings the link reported as `target` and scrolls it into view, after taking the ring off the one before.
  /// An empty `target` only takes it off. The page keeps the outline it had.
  static let point = #"""
    for (const el of document.querySelectorAll('[data-loci-pointed]')) {
      el.style.outline = el.getAttribute('data-loci-outline') || '';
      el.style.outlineOffset = el.getAttribute('data-loci-offset') || '';
      el.removeAttribute('data-loci-pointed');
    }
    if (!target || !window.__lociKey) return;
    for (const a of document.querySelectorAll('a[href]')) {
      let u; try { u = new URL(a.href, location.href); } catch { continue; }
      if (window.__lociKey(u) !== target) continue;
      const el = a.closest('ytd-rich-item-renderer, ytd-grid-video-renderer, ytd-video-renderer, ytd-playlist-video-renderer, .bili-video-card') || a;
      el.setAttribute('data-loci-outline', el.style.outline);
      el.setAttribute('data-loci-offset', el.style.outlineOffset);
      el.setAttribute('data-loci-pointed', '');
      el.style.outline = '2px solid rgba(29, 27, 24, 0.85)';
      el.style.outlineOffset = '4px';
      el.scrollIntoView({ block: 'center', behavior: 'smooth' });
      return;
    }
    """#

  /// Text this long or longer in one block, or in the body of a page with no block, reads as an article; Chinese
  /// and Japanese say more per character.
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
      const paper = (u) => {
        const host = u.hostname.replace(/^www\./, '');
        const arxiv = u.pathname.match(/^\/(abs|pdf)\/([^/]+?)(\.pdf)?$/);
        if (host === 'arxiv.org' && arxiv) return 'https://arxiv.org/abs/' + arxiv[2];
        if (/\.pdf$/i.test(u.pathname)) return u.origin + u.pathname + u.search;
        return null;
      };
      window.__lociKey = (u) => watch(u) || paper(u) || u.href;
      const controls = [
        'button', '[role=button]', 'yt-button-shape', 'ytd-button-renderer', 'button-view-model',
        '[class*="ButtonShape"]', '[class*="button-shape"]', 'header', 'ytd-playlist-header-renderer',
        'ytd-playlist-sidebar-renderer', 'yt-page-header-renderer',
      ].join(', ');
      const textOf = (el) => (el && el.textContent || '').replace(/\s+/g, ' ').trim();
      const generic = /^(pdf|slides?|paper|video|youtube|bilibili|vimeo|watch|link|here|download|视频|幻灯片|论文|下载|链接)$/i;
      const entry = (a) => {
        let box = a.parentElement;
        while (box && /^(TD|TH|TR|TBODY|TABLE|SPAN|EM|STRONG|B|I|SMALL)$/.test(box.tagName)) box = box.parentElement;
        if (!box) return '';
        let lead = '';
        for (const node of box.childNodes) {
          if (node === a || (node.contains && node.contains(a))) break;
          if (node.nodeType === 1 && /^(TABLE|UL|OL|DIV|P|IMG|BR|SCRIPT|STYLE)$/.test(node.tagName)) {
            if (lead.trim()) break;
            continue;
          }
          lead += node.textContent;
        }
        lead = lead.replace(/\s+/g, ' ').replace(/[\s:：,，(（-]+$/, '').trim();
        return lead.length > 3 && lead.length < 300 ? lead : '';
      };
      const nameOf = (a) => {
        const own = a.getAttribute('title') || textOf(a);
        return own && !generic.test(own) ? own : entry(a) || own;
      };
      const onVideoSite = /(^|\.)(youtube\.com|bilibili\.com)$/.test(location.hostname);
      const report = () => {
        const here = watch(new URL(location.href));
        const found = new Map();
        for (const a of document.querySelectorAll('a[href]')) {
          if (a.closest(controls)) continue;
          let u; try { u = new URL(a.href, location.href); } catch { continue; }
          const key = watch(u);
          if (!key || key === here) continue;
          const v = found.get(key) || { url: key };
          const titled = a.getAttribute('title') || textOf(a.querySelector('#video-title, h3, .title'))
            || (a.closest('h3, #video-title') ? textOf(a) : '');
          const named = titled || a.getAttribute('aria-label');
          const written = a.querySelector('img') ? '' : textOf(a);
          if (named && named.length < 300 && !v.named) { v.title = named; v.named = true; }
          if (!v.title && written && written.length < 300) v.title = written;
          const img = a.querySelector('img');
          if (!v.thumbnail && img && img.src && img.src.startsWith('http')) v.thumbnail = img.src;
          const time = textOf(a.querySelector('[class*="BadgeShapeHost"], .badge-shape-wiz__text, ytd-thumbnail-overlay-time-status-renderer, .bili-video-card__stats__duration, .duration'));
          if (!v.duration && /^\d{1,2}(:\d{2}){1,2}$/.test(time)) v.duration = time;
          if (!onVideoSite && !v.named && !img) {
            const linked = nameOf(a);
            if (linked && linked.length < 300) { v.title = linked; v.named = true; v.card = true; }
          }
          if (titled || v.thumbnail || v.duration) v.card = true;
          found.set(key, v);
          if (found.size >= 60) break;
        }
        const self = paper(new URL(location.href));
        const papers = new Map();
        for (const a of document.querySelectorAll('a[href]')) {
          let u; try { u = new URL(a.href, location.href); } catch { continue; }
          const key = paper(u);
          if (!key || key === self || papers.has(key)) continue;
          const title = nameOf(a);
          if (!title || title.length >= 300) continue;
          papers.set(key, { url: key, title });
          if (papers.size >= 30) break;
        }
        const framed = [...document.querySelectorAll('article, main, [role=main], .post-content, .entry-content, #content')];
        const blocks = framed.length ? framed : [document.body];
        const longest = Math.max(0, ...blocks.map((b) => [...b.querySelectorAll('p')].map(textOf).join('').length));
        const cjk = /[぀-ヿ㐀-鿿]/.test(document.title + textOf(document.querySelector('p')));
        window.webkit.messageHandlers.loci.postMessage({
          videos: [...found.values()].filter((v) => v.title && v.card).map((v) => {
            const id = v.url.match(/youtube\.com\/watch\?v=([\w-]+)/);
            return v.thumbnail || !id ? v : { ...v, thumbnail: 'https://i.ytimg.com/vi/' + id[1] + '/mqdefault.jpg' };
          }),
          papers: [...papers.values()],
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
