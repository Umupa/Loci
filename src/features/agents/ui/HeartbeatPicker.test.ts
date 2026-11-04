// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

let saved: string | null = null;
vi.mock("../model/agentFiles", async (original) => ({
  ...(await original<object>()),
  readAgentFile: vi.fn(async () => ({ text: saved, hash: "h" })),
  editAgentFile: vi.fn(async (_agent: string, _path: string, edit: (text: string) => string) => {
    saved = edit(saved ?? "");
    return "h2";
  }),
  subscribeAgentFiles: () => () => undefined,
}));

const { HeartbeatPicker } = await import("./HeartbeatPicker");

let root: Root;
let container: HTMLDivElement;
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  saved = null;
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

const button = () => container.querySelector<HTMLButtonElement>("button[aria-haspopup='menu']")!;

it("shows the default and saves the interval picked to heartbeat.json", async () => {
  await act(async () => root.render(createElement(HeartbeatPicker, { agentId: "a" })));
  expect(button().textContent).toBe("30 min");
  await act(async () => button().click());
  const options = [...document.querySelectorAll<HTMLButtonElement>("[role='menuitemradio']")];
  expect(options.map((option) => option.textContent)).toEqual(["Off", "15 min", "30 min", "1 h", "2 h"]);
  await act(async () => options[3].click());
  expect(JSON.parse(saved!)).toMatchObject({ minutes: 60 });
  expect(button().textContent).toBe("1 h");
});

it("starts over from now when turned back on", async () => {
  saved = JSON.stringify({ minutes: 0, lastRunAt: 5, quietStreak: 4, recent: ["x"] });
  await act(async () => root.render(createElement(HeartbeatPicker, { agentId: "a" })));
  expect(button().textContent).toBe("Off");
  await act(async () => button().click());
  await act(async () => document.querySelectorAll<HTMLButtonElement>("[role='menuitemradio']")[1].click());
  expect(JSON.parse(saved!)).toEqual({ minutes: 15, lastRunAt: 0, quietStreak: 0, recent: ["x"] });
});
