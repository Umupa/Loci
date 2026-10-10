import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { WidgetCard } from "./WidgetCard";

describe("widget card source states", () => {
  it("does not run a source that is still being generated", () => {
    const html = renderToStaticMarkup(createElement(WidgetCard, { source: '<script>alert("unfinished")</script>', incomplete: true }));
    expect(html).toContain("Building an interactive explanation");
    expect(html).not.toContain("<iframe");
    expect(html).not.toContain("<script");
  });

  it("shows an error and readable escaped source for malformed metadata", () => {
    const html = renderToStaticMarkup(createElement(WidgetCard, { source: '<script>alert("invalid")</script>', incomplete: false }));
    expect(html).toContain('role="alert"');
    expect(html).toContain("View source");
    expect(html).toContain("&lt;script&gt;");
    expect(html).not.toContain("<script");
    expect(html).not.toContain("<iframe");
  });
});
