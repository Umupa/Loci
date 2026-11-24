window.loci = (() => {
  const post = (message) => window.webkit.messageHandlers.book.postMessage(message);
  for (const image of document.images) image.loading = 'eager';
  const style = document.createElement('style');
  (document.head || document.documentElement).appendChild(style);
  const range = document.createRange();
  let width = innerWidth;
  let margin = 0;
  let shift = 0;

  function layout(css, edge, language) {
    if (language && !document.documentElement.getAttribute('lang') && !document.documentElement.getAttribute('xml:lang')) {
      document.documentElement.setAttribute('lang', language);
    }
    style.textContent = css;
    width = innerWidth;
    margin = edge;
    if (!/^(zh|ja)/i.test(document.documentElement.lang || document.documentElement.getAttribute('xml:lang') || '')) {
      for (const block of document.querySelectorAll('p, div, li')) {
        if (getComputedStyle(block).textAlign === 'justify') block.style.setProperty('text-align', 'start', 'important');
      }
    }
  }

  function pages() {
    const moved = document.body.style.transform;
    document.body.style.transform = '';
    const total = (document.scrollingElement || document.documentElement).scrollWidth;
    document.body.style.transform = moved;
    return Math.max(1, Math.ceil((total - 2) / width));
  }

  function go(page) {
    shift = page * width;
    document.body.style.transform = `translateX(${-shift}px)`;
    return page;
  }

  function pathOf(node) {
    const path = [];
    while (node && node !== document.body) {
      path.unshift(Array.prototype.indexOf.call(node.parentNode.childNodes, node));
      node = node.parentNode;
    }
    return path;
  }

  function nodeAt(path) {
    let node = document.body;
    for (const index of path) node = node && node.childNodes[index];
    return node || null;
  }

  function texts() {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => (node.data.trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP),
    });
    const all = [];
    let node;
    while ((node = walker.nextNode())) all.push(node);
    return all;
  }

  function lastRight(node) {
    range.selectNodeContents(node);
    const rects = range.getClientRects();
    return rects.length ? rects[rects.length - 1].right : -Infinity;
  }

  function characterRight(node, index) {
    range.setStart(node, index);
    range.setEnd(node, index + 1);
    const rect = range.getClientRects()[0];
    return rect ? rect.right : -Infinity;
  }

  function spot() {
    const all = texts();
    let low = 0;
    let high = all.length;
    while (low < high) {
      const middle = (low + high) >> 1;
      if (lastRight(all[middle]) > 1) high = middle;
      else low = middle + 1;
    }
    if (low >= all.length) return null;
    const node = all[low];
    let first = 0;
    let last = node.data.length - 1;
    while (first < last) {
      const middle = (first + last) >> 1;
      if (characterRight(node, middle) > 1) last = middle;
      else first = middle + 1;
    }
    return { node: pathOf(node), character: first };
  }

  function pageOfRect(rect) {
    return rect ? Math.max(0, Math.floor((rect.left + shift + 1) / width)) : null;
  }

  function pageOf(path, character) {
    const node = nodeAt(path);
    if (!node) return null;
    if (node.nodeType !== Node.TEXT_NODE) return pageOfRect(node.getBoundingClientRect());
    const at = Math.min(character, Math.max(0, node.length - 1));
    range.setStart(node, at);
    range.setEnd(node, Math.min(at + 1, node.length));
    return pageOfRect(range.getClientRects()[0]);
  }

  function pageOfAnchor(id) {
    const element = document.getElementById(id);
    return element ? pageOfRect(element.getClientRects()[0] || element.getBoundingClientRect()) : null;
  }

  async function ready() {
    const pictures = [...document.images].map((image) =>
      image.complete ? 0 : new Promise((done) => { image.onload = image.onerror = done; }));
    await Promise.race([Promise.all(pictures), new Promise((done) => setTimeout(done, 3000))]);
    await document.fonts.ready;
    return pages();
  }

  function broken() {
    return document.getElementsByTagName('parsererror').length > 0;
  }

  addEventListener('keydown', (event) => {
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    const forward = event.key === 'ArrowRight' || event.key === 'PageDown' || (event.key === ' ' && !event.shiftKey);
    const backward = event.key === 'ArrowLeft' || event.key === 'PageUp' || (event.key === ' ' && event.shiftKey);
    if (!forward && !backward) return;
    event.preventDefault();
    post({ turn: forward ? 1 : -1 });
  });

  let swept = 0;
  let held = false;
  let quiet = null;
  addEventListener('wheel', (event) => {
    event.preventDefault();
    clearTimeout(quiet);
    quiet = setTimeout(() => { held = false; swept = 0; }, 180);
    if (held) return;
    swept += Math.abs(event.deltaX) >= Math.abs(event.deltaY) ? event.deltaX : event.deltaY;
    if (Math.abs(swept) < 40) return;
    post({ turn: swept > 0 ? 1 : -1 });
    held = true;
    swept = 0;
  }, { passive: false });

  addEventListener('click', (event) => {
    const link = event.target.closest && event.target.closest('a[href]');
    if (link) {
      event.preventDefault();
      post({ link: link.href });
      return;
    }
    if (!getSelection().isCollapsed) return;
    if (event.clientX < margin) post({ turn: -1 });
    else if (event.clientX > innerWidth - margin) post({ turn: 1 });
  });

  return { layout, pages, go, spot, pageOf, pageOfAnchor, ready, broken };
})();
