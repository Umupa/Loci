import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * A reply's Copy / Save actions used to be hidden until hover, which on a
 * touch screen left them unreachable. The reveal stays, but only where a
 * fine pointer can hover.
 */
const CSS = readFileSync(resolve(process.cwd(), "src/styles/index.css"), "utf8").replace(/\/\*[\s\S]*?\*\//g, "");
const TARGET = "[data-turn-actions]";

/** The at-rule preludes (`@media …`) still open at `index`. */
function enclosingAtRules(css: string, index: number): string[] {
  const open: string[] = [];
  let depth = 0;
  let statementStart = 0;
  for (let at = 0; at < index; at++) {
    const char = css[at];
    if (char === "{") {
      const prelude = css.slice(statementStart, at).trim();
      open[depth] = prelude.startsWith("@") ? prelude : "";
      depth += 1;
      statementStart = at + 1;
    } else if (char === "}") {
      depth = Math.max(0, depth - 1);
      open.length = depth;
      statementStart = at + 1;
    } else if (char === ";" && depth === 0) {
      statementStart = at + 1;
    }
  }
  return open.slice(0, depth).filter(Boolean);
}

/** Every declaration block in the stylesheet whose selector targets the row. */
function turnActionRules() {
  const found: { selector: string; body: string; atRules: string[] }[] = [];
  for (let at = CSS.indexOf(TARGET); at !== -1; at = CSS.indexOf(TARGET, at + 1)) {
    const open = CSS.indexOf("{", at);
    const bodyEnd = CSS.indexOf("}", open);
    if (open === -1 || bodyEnd === -1) continue;
    // The selector runs from the previous block boundary to the brace.
    const start = Math.max(CSS.lastIndexOf("}", at), CSS.lastIndexOf("{", at)) + 1;
    found.push({
      selector: CSS.slice(start, open).replace(/\s+/g, " ").trim(),
      body: CSS.slice(open + 1, bodyEnd).replace(/\s+/g, ""),
      atRules: enclosingAtRules(CSS, start),
    });
  }
  return found;
}

describe("turn actions on touch", () => {
  it("hides a reply's actions only where the pointer can hover", () => {
    const hiding = turnActionRules().filter((rule) => rule.body.includes("opacity:0"));
    expect(hiding.length).toBeGreaterThan(0);
    for (const rule of hiding) {
      expect(rule.atRules.some((at) => at.includes("hover: hover") && at.includes("pointer: fine"))).toBe(true);
    }
  });

  it("still reveals the row on hover and keyboard focus", () => {
    const shown = turnActionRules().filter((rule) => rule.body.includes("opacity:1"));
    expect(shown.length).toBeGreaterThan(0);
    expect(shown.some((rule) => rule.selector.includes(":hover"))).toBe(true);
    expect(shown.some((rule) => rule.selector.includes(":focus-within"))).toBe(true);
  });
});
