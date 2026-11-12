// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { chatShown, DEFAULT_MENTOR_VIEW, readingLesson, useMentorView, type MentorView } from "./useMentorView";

vi.mock("../../features/agents/model/mentorStore", () => ({ mirrorViewState: () => undefined }));

it("folds the conversation while a lesson's text is read, remembering each layout's choice apart", async () => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  const lesson = { kind: "course" as const, course: { courseId: "k8s", agentId: "a", title: "K8s", itemId: "pods" } };
  expect(readingLesson({ page: lesson, lesson: { id: "pods", title: "Pods", view: "text" } })).toBe(true);
  expect(readingLesson({ page: lesson, lesson: { id: "pods", title: "Pods", view: "original" } })).toBe(false);
  expect(chatShown(DEFAULT_MENTOR_VIEW)).toBe(true);
  let view!: MentorView;
  const Probe = () => { view = useMentorView(); return null; };
  const root = createRoot(document.createElement("div"));
  await act(async () => root.render(createElement(Probe)));
  await act(async () => { view.show("a", lesson); view.setLesson("a", { id: "pods", title: "Pods", view: "text" }); });
  expect(chatShown(view.stateFor("a"))).toBe(false);
  await act(async () => view.toggleChat("a"));
  expect(chatShown(view.stateFor("a"))).toBe(true);
  expect(view.stateFor("a").chat).toBe(true);
  await act(async () => view.toggleChat("a"));
  await act(async () => view.close("a"));
  // Off the lesson, the conversation is as it was.
  expect(chatShown(view.stateFor("a"))).toBe(true);
  await act(async () => view.toggleLibrary("a"));
  expect(view.stateFor("a").library).toBe(false);
  expect(JSON.parse(localStorage.getItem("loci:agent-overviews.v1")!).a.readingChat).toBe(false);
  act(() => root.unmount());
});
