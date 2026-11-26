/// Readies a page for defuddle, so what a reader sees on it survives: a diagram drawn in the page becomes a
/// picture of its own, in ink on paper; a picture still loading keeps its frame; text meant only for screen
/// readers and line numbers go; a code card's caption gives its code a language and keeps its file name apart.
/// Defines `lociTidy(page, live, drawings)`: `live` says the page is laid out and its styles can be read, and
/// `drawings` whether diagrams become pictures.
enum PageTidying {
  static let script = #"""
    const lociTidy = (page, live, drawings) => {
      const ink = [43, 42, 39], paper = "#fbfaf7";
      const languages = {
        python: "python", py: "python", toml: "toml", bash: "bash", sh: "bash", shell: "bash", zsh: "bash",
        console: "bash", terminal: "bash", json: "json", yaml: "yaml", yml: "yaml", javascript: "javascript",
        js: "javascript", typescript: "typescript", ts: "typescript", tsx: "tsx", jsx: "jsx", go: "go",
        golang: "go", rust: "rust", dockerfile: "dockerfile", docker: "dockerfile", sql: "sql", html: "html",
        xml: "xml", css: "css", swift: "swift", ruby: "ruby", java: "java", kotlin: "kotlin", c: "c",
        "c++": "cpp", cpp: "cpp", "c#": "csharp", csharp: "csharp", php: "php", diff: "diff", text: "text",
        "plain text": "text", plaintext: "text", powershell: "powershell", makefile: "makefile", hcl: "hcl",
        lua: "lua", scala: "scala", ini: "ini", protobuf: "protobuf", graphql: "graphql", nginx: "nginx"
      };
      const quiet = "button, svg, [role=button]";

      const swatch = live ? page.createElement("canvas").getContext("2d", { willReadFrequently: true }) : null;
      const parse = color => {
        if (!color) return null;
        if (swatch) {
          swatch.clearRect(0, 0, 1, 1);
          swatch.fillStyle = "rgba(0, 0, 0, 0)";
          swatch.fillStyle = color;
          swatch.fillRect(0, 0, 1, 1);
          const [r, g, b, a] = swatch.getImageData(0, 0, 1, 1).data;
          return [r, g, b, a / 255];
        }
        const parts = /rgba?\(([^)]+)\)/.exec(color);
        if (!parts) return null;
        const [r, g, b, a = 1] = parts[1].split(/[\s,\/]+/).filter(Boolean).map(Number);
        return [r, g, b, a];
      };
      const brightness = ([r, g, b]) => (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
      const background = (() => {
        if (!live) return [255, 255, 255, 1];
        for (const element of [page.body, page.documentElement]) {
          const color = element && parse(getComputedStyle(element).backgroundColor);
          if (color && color[3] > 0) return color;
        }
        return [255, 255, 255, 1];
      })();
      const darkPage = brightness(background) < 0.5;
      const hex = channels => "#" + channels.map(value => Math.round(value).toString(16).padStart(2, "0")).join("");
      const inkText = hex(ink);
      const onPaper = color => {
        const parsed = parse(color);
        if (!parsed) return [inkText, 1];
        const [r, g, b, a] = parsed;
        if (a === 0) return ["none", 1];
        if (!darkPage) return [hex([r, g, b]), a];
        const shift = 255 - Math.max(r, g, b) - Math.min(r, g, b);
        return [hex([r + shift, g + shift, b + shift]), a];
      };
      const drawnStyles = ["stroke-dasharray", "stroke-width", "stroke-linecap", "stroke-linejoin", "font-size",
        "font-family", "font-weight", "font-style", "text-anchor", "dominant-baseline", "letter-spacing",
        "opacity"];

      const box = svg => {
        const view = (svg.getAttribute("viewBox") ?? "").split(/[\s,]+/).map(Number);
        if (view.length === 4 && view[2] > 0 && view[3] > 0) return view;
        const rect = live ? svg.getBoundingClientRect() : null;
        const width = parseFloat(svg.getAttribute("width")) || rect?.width || 0;
        const height = parseFloat(svg.getAttribute("height")) || rect?.height || 0;
        return [0, 0, width, height];
      };
      for (const svg of drawings ? [...page.querySelectorAll("svg")] : []) {
        if (!svg.isConnected || svg.parentElement?.closest("svg")) continue;
        if (svg.closest("a, button, nav, header, footer, [role=button]")) continue;
        const [x, y, width, height] = box(svg);
        if (width < 120 || height < 60) continue;
        if (!svg.querySelector("path, rect, line, polyline, polygon, circle, ellipse, text")) continue;
        const copy = svg.cloneNode(true);
        if (live) {
          const originals = [svg, ...svg.querySelectorAll("*")];
          const copies = [copy, ...copy.querySelectorAll("*")];
          const moving = [];
          originals.forEach((element, index) => {
            const kept = copies[index], style = getComputedStyle(element);
            const path = style.getPropertyValue("offset-path");
            if (element.matches("animate, animateMotion, animateTransform, set") || (path && path !== "none")) {
              moving.push(kept);
              return;
            }
            for (const name of drawnStyles) {
              const value = style.getPropertyValue(name);
              if (value) kept.setAttribute(name, value);
            }
            const unseen = element.closest("defs, marker, pattern, symbol, clipPath, mask");
            for (const part of ["fill", "stroke"]) {
              const value = style.getPropertyValue(part);
              if (value === "none" || value.startsWith("url(")) {
                kept.setAttribute(part, value);
                continue;
              }
              const [color, alpha] = unseen ? [inkText, 1] : onPaper(value);
              kept.setAttribute(part, color);
              const given = parseFloat(style.getPropertyValue(part + "-opacity"));
              const opacity = Number.isNaN(given) ? 1 : given;
              kept.setAttribute(part + "-opacity", Math.round(opacity * alpha * 100) / 100);
            }
            kept.removeAttribute("class");
            kept.removeAttribute("style");
          });
          for (const part of moving) part.remove();
        }
        copy.setAttribute("xmlns", "http://www.w3.org/2000/svg");
        copy.setAttribute("viewBox", `${x} ${y} ${width} ${height}`);
        copy.setAttribute("width", width);
        copy.setAttribute("height", height);
        const sheet = page.createElementNS("http://www.w3.org/2000/svg", "rect");
        for (const [name, value] of [["x", x], ["y", y], ["width", width], ["height", height], ["fill", paper]])
          sheet.setAttribute(name, value);
        copy.insertBefore(sheet, copy.firstChild);
        const markup = new XMLSerializer().serializeToString(copy).replace(/currentColor/gi, inkText);
        const picture = page.createElement("img");
        picture.setAttribute("src", "data:image/svg+xml;base64," + btoa(unescape(encodeURIComponent(markup))));
        picture.setAttribute("alt", (svg.querySelector("title")?.textContent ?? svg.getAttribute("aria-label") ?? "").trim());
        picture.setAttribute("width", Math.round(width));
        picture.setAttribute("height", Math.round(height));
        svg.replaceWith(picture);
      }

      for (const picture of page.querySelectorAll('img[loading="lazy"]')) picture.setAttribute("loading", "eager");
      for (const element of [...page.querySelectorAll("[class]")]) {
        if (!element.matches("img, picture, video") && !element.querySelector("img, picture, video")) continue;
        const names = [...element.classList].filter(name => /loading|skeleton|placeholder|shimmer/i.test(name));
        for (const name of names) element.classList.remove(name);
      }

      const hidden = '.sr-only, .visually-hidden, .screen-reader-text, .screen-reader-only, [aria-hidden="true"]';
      for (const element of [...page.querySelectorAll(hidden)]) {
        if (!element.isConnected || element.matches("html, body, main, article, img, picture, video")) continue;
        if (element.closest(".katex, .MathJax, mjx-container, math, [data-mathml]")) continue;
        if (element.querySelector("img, picture, video, math, p, li, table, figure, h1, h2, h3, h4, h5, h6")) continue;
        element.remove();
      }

      const words = element => {
        const found = [];
        const walker = page.createTreeWalker(element, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const text = node.textContent.trim();
          if (text && !node.parentElement.closest(quiet)) found.push(text);
        }
        return found;
      };
      for (const pre of [...page.querySelectorAll("pre")]) {
        if (!pre.isConnected || !pre.textContent.trim()) continue;
        const code = pre.querySelector("code") ?? pre;
        let branch = pre;
        for (let depth = 0; depth < 4 && branch.parentElement; depth++) {
          const card = branch.parentElement;
          if (card.matches("body, main, article, section") || card.querySelectorAll("pre").length > 1) break;
          const others = [...card.children].filter(child => child !== branch);
          if (others.length === 0) {
            branch = card;
            continue;
          }
          const prose = "p, ul, ol, table, blockquote, img, picture, figure, pre, h1, h2, h3";
          if (others.length > 3 || others.some(other => other.matches(prose) || other.querySelector(prose))) break;
          const caption = others.flatMap(words);
          if (caption.join(" ").length > 80) break;
          const marked = others
            .map(other => other.matches('[class*="lang"]') ? other : other.querySelector('[class*="lang"]'))
            .find(Boolean)?.textContent.trim().toLowerCase();
          const spoken = marked && languages[marked] ? marked
            : [...caption].reverse().map(word => word.toLowerCase()).find(word => languages[word]);
          const names = caption.filter(word => word.toLowerCase() !== spoken);
          if (!spoken && names.length === 0 && others.every(other => !other.querySelector(quiet) && !other.matches(quiet))) break;
          if (spoken && ![...code.classList].some(name => /^(language|lang)-/.test(name)))
            code.classList.add("language-" + languages[spoken]);
          for (const other of others) other.remove();
          if (names.length > 0) {
            const label = page.createElement("p");
            label.textContent = names.join(" ");
            card.parentElement?.insertBefore(label, card);
          }
          break;
        }
      }
    };
    """#
}
