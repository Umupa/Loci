// @vitest-environment happy-dom
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { AgentMarkdown } from "./AgentMarkdown";

const predicates = String.raw`\text{PodScheduled} \xrightarrow{\text{通过}} \text{Initialized} \xrightarrow{\text{通过}} \text{ContainersReady} \xrightarrow{\text{通过}} \mathrm{Ready}`;

function render(text: string, wholeDocument = false) {
  const container = document.createElement("div");
  container.innerHTML = renderToStaticMarkup(createElement(AgentMarkdown, { text, wholeDocument }));
  return container;
}

describe("AgentMarkdown math", () => {
  it.each([false, true])("renders the Pod predicates inside a list (wholeDocument: %s)", (wholeDocument) => {
    const container = render(`- 控制面真正关心的是**谓词（Predicates）**： $$${predicates}$$`, wholeDocument);
    const item = container.querySelector("li")!;
    expect(item.querySelector(".katex")).not.toBeNull();
    expect(item.querySelector("math")).not.toBeNull();
    expect(item.querySelector("annotation")?.textContent).toBe(predicates);
    expect(item.querySelector(".katex-html")?.textContent).toContain("PodScheduled");
    expect(item.querySelector(".katex-html")?.textContent).toContain("通过");
    expect(item.querySelector(".katex-html")?.textContent).toContain("Ready");
    expect(item.querySelector(".katex-error")).toBeNull();
  });

  it("renders conventional single-dollar inline formulas", () => {
    const container = render(String.raw`如果 $\Delta \neq 0$，控制器继续调谐。`);
    expect(container.querySelector(".katex")).not.toBeNull();
    expect(container.querySelector("annotation")?.textContent).toBe(String.raw`\Delta \neq 0`);
    expect(container.querySelector(".katex-display")).toBeNull();
  });

  it("renders multiline display math as an equation", () => {
    const container = render("$$\n\\frac{a}{b} = \\Delta\n$$", true);
    expect(container.querySelector(".katex-display math mfrac")).not.toBeNull();
    expect(container.querySelector("annotation")?.textContent).toBe(String.raw`\frac{a}{b} = \Delta`);
  });

  it("preserves formula examples in code and escaped currency", () => {
    const container = render([
      String.raw`Rendered: $$\Delta$$.`,
      "Inline example: `$$\\Delta$$`.",
      "```text\n$$\\Delta$$\n```",
      String.raw`Prices: \$5 and \$10.`,
    ].join("\n\n"));
    expect(container.querySelectorAll(".katex")).toHaveLength(1);
    expect(container.querySelector("p code")?.textContent).toContain(String.raw`$$\Delta$$`);
    expect(container.querySelector("pre")?.textContent).toContain(String.raw`$$\Delta$$`);
    expect(container.textContent).toContain("Prices: $5 and $10.");
  });
});
