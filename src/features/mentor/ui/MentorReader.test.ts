// @vitest-environment happy-dom
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { expect, it, vi } from "vitest";
import type { Agent } from "../../agents/model/agent";
import { MentorReader } from "./MentorReader";

vi.mock("../../files/ui/FilePane", () => ({ FilePane: () => createElement("section", { "data-test-file": true }) }));

const agent: Agent = { id: "agent-a", sessionId: "chat-a", name: "Ada", avatar: "loci", color: "#123456" };

const base = {
  agent, request: 0, onClose: () => {}, onLessonChange: () => {}, onBeforeLeave: () => {},
  onOpenFile: () => {}, renderSession: () => null, sessionTitle: () => "",
};

it("names the file it is opening while its pane's code arrives", () => {
  const html = renderToStaticMarkup(createElement(MentorReader, { ...base, page: { kind: "file", path: "/src/main.rs" } }));
  expect(html).toContain("Opening main.rs…");
});
