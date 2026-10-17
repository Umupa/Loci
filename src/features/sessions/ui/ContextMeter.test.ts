// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { ContextMeter } from "./ContextMeter";

let container: HTMLDivElement;
let root: Root;
const render = (props: Parameters<typeof ContextMeter>[0]) => act(() => root.render(createElement(ContextMeter, props)));

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe("ContextMeter", () => {
  it("says the percentage and the tokens beside the ring when asked", () => {
    render({ usage: { used: 176_000, window: 256_000 }, detailed: true });
    expect(container.textContent).toContain("69%");
    expect(container.textContent).toContain("Tokens: 176K");
    expect(container.querySelector("svg")).not.toBeNull();
  });

  it("stays a bare ring by default", () => {
    render({ usage: { used: 176_000, window: 256_000 } });
    expect(container.textContent).toBe("");
    expect(container.querySelector("svg")).not.toBeNull();
  });

  it("gives just the tokens, no ring or percentage, when the window is unknown", () => {
    render({ usage: { used: 4_200 }, detailed: true });
    expect(container.querySelector("svg")).toBeNull();
    expect(container.textContent).toBe("Tokens: 4.2K");
    // Without the detail there is nothing honest to draw.
    render({ usage: { used: 4_200 } });
    expect(container.textContent).toBe("");
  });

  it("draws nothing before the harness reports anything", () => {
    render({ detailed: true });
    expect(container.textContent).toBe("");
  });

  it("tints the numbers as the window fills", () => {
    render({ usage: { used: 240_000, window: 256_000 }, detailed: true });
    expect(container.querySelector("span.text-red-400")?.textContent).toContain("94%");
  });
});


it("shows an unknown empty ring in the agent toolbar without a false percentage or progress dot", () => {
  render({ empty: true });
  expect(container.querySelector('svg[role="img"]')?.getAttribute("aria-label")).toBe("Context usage not reported yet");
  expect(container.querySelectorAll("circle")).toHaveLength(1);
  expect(container.textContent).not.toContain("0%");
});
