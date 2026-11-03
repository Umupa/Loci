// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { setAgentReading, setAgentReadingPlace, takeReadingContext } from "../../agents/model/agentReading";
import { setLanguagePreference } from "../../../shared/i18n/locale";
import { ReadingTag } from "./ReadingTag";

let root: Root;
let host: HTMLDivElement;
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  setLanguagePreference("en");
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});
afterEach(async () => {
  await act(async () => root.unmount());
  host.remove();
  setLanguagePreference("system");
  vi.unstubAllGlobals();
});

it("shows the open page and place, follows the reader, and leaves the page out of one message", async () => {
  await act(async () => root.render(createElement(ReadingTag, { agentId: "tag-ui" })));
  expect(host.querySelector("[data-reading-tag]")).toBeNull();

  await act(async () => setAgentReading("tag-ui", { kind: "document", id: "fc", title: "Firecracker" }));
  await act(async () => setAgentReadingPlace("tag-ui", { page: 3, selection: { text: "a\nb", page: 3 } }));
  const tag = () => host.querySelector("[data-reading-tag]")!;
  expect(tag().textContent).toContain("Firecracker · p. 3 · 2 lines selected");

  await act(async () => setLanguagePreference("zh-CN"));
  expect(tag().textContent).toContain("Firecracker · 第 3 页 · 已选 2 行");

  await act(async () => (host.querySelector("button") as HTMLButtonElement).click());
  expect(tag().getAttribute("data-reading-tag")).toBe("skipped");
  // Sending takes the dismissal: this turn goes without, and the tag comes back.
  await act(async () => { expect(takeReadingContext("tag-ui")).toBeUndefined(); });
  expect(tag().getAttribute("data-reading-tag")).toBe("");
  expect(takeReadingContext("tag-ui")).toContain("<reading_now>");

  await act(async () => setAgentReading("tag-ui", undefined));
  expect(host.querySelector("[data-reading-tag]")).toBeNull();
});
