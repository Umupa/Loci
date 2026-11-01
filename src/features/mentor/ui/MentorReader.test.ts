// @vitest-environment happy-dom
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, expect, it, vi } from "vitest";
import { invalidateCanvases, type Canvas } from "../../canvas/canvas";
import type { Agent } from "../../agents/model/agent";
import { MentorReader } from "./MentorReader";

vi.mock("../../canvas/ui/CanvasPane", () => ({ CanvasPane: () => createElement("section", { "data-test-canvas": true }) }));
vi.mock("../../files/ui/FilePane", () => ({ FilePane: () => createElement("section", { "data-test-file": true }) }));

const agent: Agent = { id: "agent-a", sessionId: "chat-a", name: "Ada", avatar: "loci", color: "#123456", projects: [] };
const other: Canvas = { id: "other-drawing", title: "Other", cwd: "", dataJson: '{"elements":[]}', tags: [], createdAt: 1, updatedAt: 2 };

const base = {
  agent, request: 0, onClose: () => {}, onLessonChange: () => {}, onBeforeLeave: () => {},
  onCanvasAddToChat: () => {}, onCanvasTitleChange: () => {}, onOpenFile: () => {}, renderSession: () => null,
};

beforeEach(() => { invalidateCanvases(); });

it("says a remembered drawing is opening until the app has listed drawings", () => {
  const html = renderToStaticMarkup(createElement(MentorReader, { ...base, canvases: [], page: { kind: "canvas", id: "remembered" } }));
  expect(html).toContain("Opening drawing…");
  expect(html).not.toContain("no longer available");
});

it("says a drawing is gone once the list is known", () => {
  const html = renderToStaticMarkup(createElement(MentorReader, { ...base, canvases: [other], page: { kind: "canvas", id: "remembered" } }));
  expect(html).toContain("This drawing is no longer available.");
  expect(html).not.toContain("Opening drawing…");
});

it("names the file it is opening while its pane's code arrives", () => {
  const html = renderToStaticMarkup(createElement(MentorReader, { ...base, canvases: [], page: { kind: "file", path: "/src/main.rs" } }));
  expect(html).toContain("Opening main.rs…");
});
