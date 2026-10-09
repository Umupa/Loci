import { describe, expect, it } from "vitest";
import {
  documentsInText,
  fencedBlocks,
  parseDocument,
  parseMindmap,
  parseCanvasLink,
  parseTodo,
} from "./cards";

describe("documents", () => {
  it("is named by its front matter, with Markdown after it", () => {
    expect(parseDocument("---\nid: Pods 101\ntitle: \"Pods, explained\"\nsubject: Kubernetes\n---\n\n# Pods\n\nA pod is…\n")).toEqual({
      id: "pods-101", title: "Pods, explained", subject: "Kubernetes", body: "# Pods\n\nA pod is…",
    });
  });

  it("takes its title and id from the first heading when it has no front matter", () => {
    expect(parseDocument("# Service 是什么\n\n正文")).toMatchObject({ id: "service-是什么", title: "Service 是什么", body: "# Service 是什么\n\n正文" });
    expect(parseDocument("Just text.")).toMatchObject({ id: "document", title: "Untitled document" });
    expect(parseDocument("   \n")).toBeUndefined();
  });

  it("finds the documents a reply wrote, code inside them and all, and keeps the last of each id", () => {
    const reply = [
      "Here is the reading.",
      "",
      "````loci-document",
      "---",
      "id: pods",
      "title: Pods",
      "---",
      "Run it:",
      "",
      "```sh",
      "kubectl get pods",
      "```",
      "````",
      "",
      "And a revision:",
      "",
      "~~~~loci-document",
      "---",
      "id: pods",
      "title: Pods, revised",
      "---",
      "Shorter.",
      "~~~~",
      "",
      "```sh",
      "echo not a document",
      "```",
    ].join("\n");
    expect(fencedBlocks(reply, "loci-document")).toHaveLength(2);
    expect(fencedBlocks(reply, "loci-document")[0]).toContain("```sh\nkubectl get pods\n```");
    expect(documentsInText(reply)).toEqual([{ id: "pods", title: "Pods, revised", body: "Shorter." }]);
  });

  it("saves nothing from a block that is still being written", () => {
    expect(documentsInText("````loci-document\n---\ntitle: Half\n---\nStill wri")).toEqual([]);
    expect(documentsInText("No blocks here.")).toEqual([]);
  });
});

describe("todo lists", () => {
  it("reads task lines, done or not, under an optional title", () => {
    expect(parseTodo("# This week\n- [x] Read about Pods\n- [ ] Try a Deployment\n* [X] Install kind\n1. [ ] Write notes")).toEqual({
      title: "This week",
      items: [
        { text: "Read about Pods", done: true },
        { text: "Try a Deployment", done: false },
        { text: "Install kind", done: true },
        { text: "Write notes", done: false },
      ],
    });
  });

  it("takes a plain bullet for a task not yet done, and is nothing without tasks", () => {
    expect(parseTodo("- Read\n- [x] Write")).toEqual({ items: [{ text: "Read", done: false }, { text: "Write", done: true }] });
    expect(parseTodo("Just a sentence.")).toBeUndefined();
    expect(parseTodo("")).toBeUndefined();
  });
});

describe("mind maps", () => {
  it("nests bullets under the line above them", () => {
    expect(parseMindmap("- Kubernetes\n  - Workloads\n    - Pod\n    - Deployment\n  - Networking\n    - Service")).toEqual({
      text: "Kubernetes",
      children: [
        { text: "Workloads", children: [{ text: "Pod", children: [] }, { text: "Deployment", children: [] }] },
        { text: "Networking", children: [{ text: "Service", children: [] }] },
      ],
    });
  });

  it("hangs bullets under the heading above them", () => {
    expect(parseMindmap("# Kubernetes\n## Workloads\n- Pod\n## Networking\n- Service\n  - ClusterIP")).toEqual({
      text: "Kubernetes",
      children: [
        { text: "Workloads", children: [{ text: "Pod", children: [] }] },
        { text: "Networking", children: [{ text: "Service", children: [{ text: "ClusterIP", children: [] }] }] },
      ],
    });
  });

  it("gathers several top branches under one root, and is nothing when empty", () => {
    expect(parseMindmap("- A\n- B")).toEqual({ text: "", children: [{ text: "A", children: [] }, { text: "B", children: [] }] });
    expect(parseMindmap("\n")).toBeUndefined();
  });
});

describe("canvas links", () => {
  it("reads the id and the name, or a bare id", () => {
    expect(parseCanvasLink("id: abc-123\ntitle: Pod lifecycle")).toEqual({ id: "abc-123", title: "Pod lifecycle" });
    expect(parseCanvasLink("abc-123\n")).toEqual({ id: "abc-123" });
    expect(parseCanvasLink("the canvas I drew")).toBeUndefined();
  });
});
