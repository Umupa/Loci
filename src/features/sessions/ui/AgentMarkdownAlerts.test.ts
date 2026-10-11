// @vitest-environment happy-dom
import { createElement, type ComponentProps } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { AgentMarkdown } from "./AgentMarkdown";

function render(text: string, props: Omit<ComponentProps<typeof AgentMarkdown>, "text"> = {}) {
  const container = document.createElement("div");
  container.innerHTML = renderToStaticMarkup(createElement(AgentMarkdown, { text, ...props }));
  return container;
}

const modes = [
  { name: "default block rendering", props: {} },
  { name: "whole document rendering", props: { wholeDocument: true } },
];

describe.each(modes)("AgentMarkdown alerts with $name", ({ props }) => {
  it.each(["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"])(
    "renders a %s alert with a title and decorative icon",
    (type) => {
      const container = render(`> [!${type}]\n> The alert body.`, props);
      const alert = container.querySelector(`blockquote[data-markdown-alert="${type.toLowerCase()}"]`);

      expect(alert).not.toBeNull();
      expect(alert?.getAttribute("data-streamdown")).toBe("blockquote");
      expect(alert?.querySelector(".markdown-alert-title")?.textContent?.trim().toLowerCase()).toBe(type.toLowerCase());
      expect(alert?.querySelector(".markdown-alert-title svg[aria-hidden=\"true\"]")).not.toBeNull();
      expect(alert?.textContent).toContain("The alert body.");
      expect(container.textContent).not.toContain(`[!${type}]`);
    },
  );

  it("keeps inline formatting, links, paragraphs and lists inside an alert", () => {
    const container = render([
      "> [!NOTE]",
      "> Read *carefully*, use `config.json`, and [visit the docs](https://example.com/docs).",
      ">",
      "> A second paragraph.",
      ">",
      "> - First item",
      "> - Second item",
    ].join("\n"), props);
    const alert = container.querySelector("[data-markdown-alert=\"note\"]");

    expect(alert?.querySelector("em")?.textContent).toBe("carefully");
    expect(alert?.querySelector("code")?.textContent).toBe("config.json");
    expect(alert?.querySelector("a")?.getAttribute("href")).toBe("https://example.com/docs");
    expect(Array.from(alert?.querySelectorAll("p") ?? [], (paragraph) => paragraph.textContent)).toEqual([
      "Read carefully, use config.json, and visit the docs.",
      "A second paragraph.",
    ]);
    expect(Array.from(alert?.querySelectorAll("li") ?? [], (item) => item.textContent)).toEqual([
      "First item",
      "Second item",
    ]);
  });

  it("accepts a quoted blank line after the marker and a case-insensitive marker", () => {
    const container = render("> [!nOtE]  \n>\n> A paragraph within the quote.", props);
    const alert = container.querySelector("[data-markdown-alert=\"note\"]");

    expect(alert).not.toBeNull();
    expect(alert?.querySelectorAll("p")).toHaveLength(1);
    expect(alert?.querySelector("p")?.textContent).toBe("A paragraph within the quote.");
    expect(container.textContent).not.toContain("[!nOtE]");
  });

  it.each([
    { name: "an ordinary quote", text: "> Quoted prose.", preserved: "Quoted prose." },
    { name: "an unknown marker", text: "> [!CUSTOM]\n> Quoted prose.", preserved: "[!CUSTOM]" },
    { name: "a marker after the first line", text: "> First line.\n> [!NOTE]\n> Quoted prose.", preserved: "[!NOTE]" },
    { name: "a marker after the first paragraph", text: "> First paragraph.\n>\n> [!NOTE]\n> Quoted prose.", preserved: "[!NOTE]" },
    { name: "a marker followed by inline content", text: "> [!NOTE] inline content\n> Quoted prose.", preserved: "[!NOTE] inline content" },
    { name: "a marker followed by inline formatting", text: "> [!NOTE]**inline**\n> Quoted prose.", preserved: "[!NOTE]inline" },
    { name: "a marker in inline code", text: "> `[!NOTE]`\n> Quoted prose.", preserved: "[!NOTE]" },
    { name: "an escaped marker", text: "> \\[!NOTE]\n> Quoted prose.", preserved: "[!NOTE]" },
    { name: "a marker written as a character reference", text: "> &#91;!NOTE]\n> Quoted prose.", preserved: "[!NOTE]" },
    { name: "a marker with an escaped closing bracket", text: "> [!NOTE\\]\n> Quoted prose.", preserved: "[!NOTE]" },
    { name: "a character reference inside the marker", text: "> [!NO&#84;E]\n> Quoted prose.", preserved: "[!NOTE]" },
  ])("preserves $name", ({ text, preserved }) => {
    const container = render(text, props);

    expect(container.querySelector("[data-markdown-alert]")).toBeNull();
    expect(container.querySelector("blockquote")?.textContent).toContain(preserved);
    expect(container.querySelector(".markdown-alert-title")).toBeNull();
  });

  it("leaves a fenced alert example as code", () => {
    const container = render("```markdown\n> [!NOTE]\n> Example body.\n```", props);

    expect(container.querySelector("[data-markdown-alert]")).toBeNull();
    expect(container.querySelector("code")?.textContent).toContain("> [!NOTE]");
    expect(container.querySelector("code")?.textContent).toContain("> Example body.");
  });

  it("keeps the independent paragraph after a bare blank line outside the alert", () => {
    const container = render("> [!NOTE]\n\nAn independent paragraph.", props);
    const alert = container.querySelector("[data-markdown-alert=\"note\"]");
    const paragraph = Array.from(container.querySelectorAll("p"))
      .find((node) => node.textContent === "An independent paragraph.");

    expect(alert).not.toBeNull();
    expect(paragraph).toBeDefined();
    expect(alert?.contains(paragraph!)).toBe(false);
    expect(alert?.textContent).not.toContain("An independent paragraph.");
  });
});

it("recognizes a completed streaming marker and keeps the growing body", () => {
  const props = { streaming: true, revealOnMount: false };
  const incomplete = render("> [!NO", props);
  expect(incomplete.querySelector("[data-markdown-alert]")).toBeNull();

  const marker = render("> [!NOTE]", props);
  expect(marker.querySelector("[data-markdown-alert=\"note\"]")).not.toBeNull();
  expect(marker.textContent).not.toContain("[!NOTE]");

  const growing = render("> [!NOTE]\n> First words", props);
  expect(growing.querySelector("[data-markdown-alert=\"note\"] p")?.textContent).toBe("First words");

  const completed = render("> [!NOTE]\n> First words and the final sentence.", props);
  expect(completed.querySelector("[data-markdown-alert=\"note\"] p")?.textContent).toBe("First words and the final sentence.");
  expect(completed.querySelectorAll("[data-markdown-alert=\"note\"] p [data-word-fade]").length).toBeGreaterThan(0);
  expect(completed.textContent).not.toContain("[!NOTE]");
});

it.each([false, true])("preserves body hard breaks when word fading is %s", (streaming) => {
  const container = render("> [!NOTE]  \n> first line\n> *second line*", {
    hardBreaks: true,
    streaming,
    revealOnMount: false,
  });
  const alert = container.querySelector("[data-markdown-alert=\"note\"]");

  expect(alert).not.toBeNull();
  expect(alert?.querySelector("p")?.textContent).toBe("first linesecond line");
  expect(alert?.querySelectorAll("br")).toHaveLength(1);
  expect(alert?.querySelector("p > br")?.nextElementSibling?.tagName).toBe("EM");
  expect(alert?.querySelector("em")?.textContent).toBe("second line");
  expect(container.textContent).not.toContain("[!NOTE]");
});
