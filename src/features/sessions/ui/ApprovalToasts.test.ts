// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { ApprovalToasts } from "./ApprovalToasts";

type Notice = ComponentProps<typeof ApprovalToasts>["notices"][number];
function notice(
  id: string,
  kind: Notice["kind"] = "approval",
  requestId = 1,
): Notice {
  return {
    sessionId: id,
    requestId,
    label: `Request ${id}`,
    kind,
    session: {
      id,
      cwd: `/projects/${id}`,
      title: id,
      harness: "codex",
      model: "",
      modelSettings: {},
      runtimeMode: "supervised",
      blocks: [],
    },
  };
}

let container: HTMLDivElement;
let root: Root;
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  onApproval.mockClear();
  onFocusSession.mockClear();
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

const onApproval = vi.fn();
const onFocusSession = vi.fn();
function render(notices: Notice[]) {
  root.render(
    createElement(ApprovalToasts, { notices, onApproval, onFocusSession }),
  );
}
function visibleRequests() {
  return [...document.querySelectorAll(".approval-toast")].map(
    (item) => item.textContent,
  );
}

it("sits below the title bar and keeps its buttons out of the status announcement", async () => {
  await act(async () => render([notice("work")]));
  const card = document.querySelector<HTMLElement>(".approval-toast")!;
  expect(card.getAttribute("role")).toBeNull();
  expect(card.parentElement!.style.top).toBe("48px");
  const status = card.querySelector('[role="status"]')!;
  expect(status.textContent).toBe("Request work");
  expect(status.querySelector("button")).toBeNull();
  expect(card.querySelector("button")!.closest('[role="status"]')).toBeNull();
});

it("shows a request in a project and its Allow answers it", async () => {
  await act(async () => render([notice("work")]));
  const allow = [...document.querySelectorAll("button")].find((item) => item.textContent === "Allow")!;
  act(() => allow.click());
  expect(onApproval).toHaveBeenCalledWith("work", 1, "allow");
});
