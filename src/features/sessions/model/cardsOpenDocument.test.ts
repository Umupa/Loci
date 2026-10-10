// @vitest-environment happy-dom
import { expect, it, vi } from "vitest";
import { OPEN_DOCUMENT_EVENT, openDocument } from "./cards";

it("sends library ownership with the document while keeping chat documents compatible", () => {
  const document = { id: "network", title: "Network strategy", body: "Egress and ingress." };
  const opened = vi.fn();
  window.addEventListener(OPEN_DOCUMENT_EVENT, opened);
  try {
    openDocument(document, "agent-a");
    openDocument(document);
    expect(opened.mock.calls.map(([event]) => (event as CustomEvent).detail)).toEqual([
      { ...document, agentId: "agent-a" }, document,
    ]);
    expect(document).not.toHaveProperty("agentId");
  } finally {
    window.removeEventListener(OPEN_DOCUMENT_EVENT, opened);
  }
});
