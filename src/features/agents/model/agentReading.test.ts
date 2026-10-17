import { expect, it } from "vitest";
import { readingContext, setAgentReading } from "./agentReading";

it("tells a turn what is open beside the chat, and nothing once it closes", () => {
  setAgentReading("mentor", { kind: "course", courseId: "k8s", title: "Kubernetes", lessonId: "pods", lessonTitle: "Pods" });
  expect(readingContext("mentor")).toBe('<reading_now>\n{"kind":"course","courseId":"k8s","title":"Kubernetes","lessonId":"pods","lessonTitle":"Pods"}\n</reading_now>');
  expect(readingContext("other")).toBeUndefined();
  setAgentReading("mentor", undefined);
  expect(readingContext("mentor")).toBeUndefined();
});
