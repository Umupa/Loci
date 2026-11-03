import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * The app shell must not be scrollable at all. With `overflow: hidden` the
 * root stays a scroll container, and a reader's `scrollIntoView({ block:
 * "start" })` (a section has `scroll-margin-top: 64px`) scrolls it: WKWebView
 * moves the whole shell up and the window's top header row — the library
 * toggle, back/forward, the conversation's settings and close — leaves the
 * viewport until the app restarts. `overflow: clip` refuses every scroll,
 * programmatic ones included, while inner readers keep their own scrollers.
 */
const CSS_PATH = resolve(process.cwd(), "src/styles/index.css");

function shellRule(): { selectors: string[]; body: string } | undefined {
  const css = readFileSync(CSS_PATH, "utf8").replace(/\/\*[\s\S]*?\*\//g, "");
  const rules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map((match) => ({
    selectors: (match[1] ?? "").split(",").map((selector) => selector.trim()),
    body: match[2] ?? "",
  }));
  return rules.find(
    (rule) =>
      ["html", "body", "#root"].every((selector) =>
        rule.selectors.includes(selector),
      ) && rule.body.includes("position: fixed"),
  );
}

describe("app shell overflow", () => {
  it("cannot be scrolled by scrollIntoView, which used to hide the header row", () => {
    const rule = shellRule();
    expect(rule).toBeDefined();
    expect(rule?.body).toMatch(/overflow:\s*clip\s*;/);
    expect(rule?.body).not.toMatch(/overflow:\s*hidden\s*;/);
  });
});
