// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { Block } from "../model/session";
import { TurnProgress } from "./TurnProgress";

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ENVIRONMENT", true);
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

function tool(id: string, title: string): Block {
  return {
    id,
    role: "tool",
    text: title,
    tool: { kind: "execute", title, status: "completed" },
  };
}

const turn: Block[] = [
  { id: "u", role: "user", text: "prepare the reading" },
  tool("a", "git clone https://github.com/tokio-rs/tokio.git"),
  tool("b", "curl https://kubernetes.io/docs/concepts/overview/"),
  tool("c", "nl -ba src/main.rs"),
  tool("d", "cargo test"),
  {
    id: "e",
    role: "tool",
    text: "Read src/lib.rs",
    tool: { kind: "read", title: "Read src/lib.rs", status: "in_progress", preview: { kind: "read", path: "/work/src/lib.rs" } },
  },
];

function render(blocks: Block[], visible = true) {
  act(() => root.render(createElement(TurnProgress, { blocks, visible })));
}

it("shows the newest three steps, newest first", () => {
  render(turn);
  expect(container.querySelector("[data-activity-newest]")?.textContent).toBe("Reading lib.rs");
  expect(
    [...container.querySelectorAll("[data-activity-entry]")].map((row) => row.textContent),
  ).toEqual(["Ran cargo test", "Ran nl -ba src/main.rs"]);
  expect(container.querySelector("[data-turn-progress]")?.getAttribute("data-activity-status")).toBe("running");
});

it("expands to the rest of the turn and folds back", () => {
  render(turn);
  const toggle = container.querySelector<HTMLButtonElement>(`button[aria-label="Show all 5 steps"]`)!;
  expect(toggle).not.toBeNull();
  act(() => toggle.click());
  expect(container.querySelectorAll("[data-activity-entry]")).toHaveLength(4);
  expect(container.querySelector("[data-activity-newest]")?.textContent).toBe("Reading lib.rs");
  act(() => container.querySelector<HTMLButtonElement>('button[aria-label="Show fewer steps"]')!.click());
  expect(container.querySelectorAll("[data-activity-entry]")).toHaveLength(2);
});

it("says it is working before the first tool reports anything", () => {
  render([{ id: "u", role: "user", text: "go" }]);
  expect(container.querySelector("[data-activity-newest]")?.textContent).toBe("Working…");
  expect(container.querySelector("[data-turn-progress]")?.getAttribute("data-activity-status")).toBe("thinking");
});
