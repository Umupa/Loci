import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { ModalPanel } from "./Modal";

describe("ModalPanel", () => {
  it("names the dialog and close action", () => {
    const markup = renderToStaticMarkup(
      createElement(ModalPanel, {
        title: "Example",
        description: "A reusable shell",
        onClose: vi.fn(),
        children: "Body",
      }),
    );

    expect(markup).toContain('role="dialog"');
    expect(markup).toContain("modal-panel");
    expect(markup).toContain("Example");
    expect(markup).toContain("A reusable shell");
    expect(markup).toContain("Body");
    expect(markup).toContain('aria-label="Close"');
  });

  it("can preserve an accessible title with a minimal visual header", () => {
    const markup = renderToStaticMarkup(
      createElement(ModalPanel, {
        title: "Authentication required",
        description: "Sign in to continue.",
        minimalHeader: true,
        onClose: vi.fn(),
        children: "Provider login",
      }),
    );

    expect(markup).toContain('class="sr-only"');
    expect(markup).toContain("Authentication required");
    expect(markup).toContain("Provider login");
  });

  it("pins a footer after the scrolling body and can disable closing", () => {
    const markup = renderToStaticMarkup(
      createElement(ModalPanel, {
        title: "Update Loci",
        onClose: vi.fn(),
        footer: "Install and Restart",
        closeDisabled: true,
        children: "Release notes",
      }),
    );

    expect(markup).toContain("Release notes");
    expect(markup).toContain("Install and Restart");
    expect(markup.indexOf("Release notes")).toBeLessThan(markup.indexOf("Install and Restart"));
    expect(markup).toMatch(/aria-label="Close"[^>]*disabled=""/);
  });
});
