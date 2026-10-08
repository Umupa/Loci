// @vitest-environment happy-dom
// The learning map keeps its state in `customData` of Excalidraw elements.
// These tests pin the library behavior that design relies on.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// The first use of Excalidraw loads all of it, which a busy machine can take longer than 5 seconds over.
vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

type El = Record<string, any>;

beforeEach(() => {
  vi.stubGlobal("FontFace", class { constructor(family: string, _source: string, descriptors: object) { Object.assign(this, { family }, descriptors); } });
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({ filter: "none", measureText: (text: string) => ({ width: text.length * 10 }) } as never);
});
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

const learn = { v: 1, kind: "concept", state: "ghost", history: [] };

describe("Excalidraw keeps customData", () => {
  it("when shapes and arrows are created from skeletons", async () => {
    const { convertToExcalidrawElements } = await import("@excalidraw/excalidraw");
    const elements = convertToExcalidrawElements([
      { type: "rectangle", id: "a", x: 0, y: 0, width: 180, height: 64, label: { text: "A" }, customData: { learn }, link: "loci://note/n1" },
      { type: "rectangle", id: "b", x: 300, y: 0, width: 180, height: 64, label: { text: "B" } },
      { type: "arrow", id: "ab", x: 180, y: 32, width: 120, height: 0, start: { id: "a" }, end: { id: "b" }, label: { text: "leads to" }, customData: { learn: { v: 1, kind: "edge", by: "learner" } } },
    ] as never, { regenerateIds: false }) as El[];
    expect(elements.find((element) => element.id === "a")).toMatchObject({ customData: { learn }, link: "loci://note/n1" });
    expect(elements.find((element) => element.id === "ab")?.customData).toEqual({ learn: { v: 1, kind: "edge", by: "learner" } });
    // A label is its own text element and does not inherit the shape's data.
    expect(elements.filter((element) => element.type === "text").every((element) => !element.customData)).toBe(true);
  });

  it("through restore, element updates and the scene normalizer", async () => {
    const { convertToExcalidrawElements, newElementWith, restore, restoreElements } = await import("@excalidraw/excalidraw");
    const { normalizeCanvasScene } = await import("../../canvas/scene");
    const [shape] = convertToExcalidrawElements([{ type: "diamond", id: "j", x: 0, y: 0, width: 200, height: 110, customData: { learn } }] as never, { regenerateIds: false }) as El[];
    expect((restoreElements([shape] as never, null, { repairBindings: true }) as El[])[0].customData).toEqual({ learn });
    expect((restore({ elements: [shape], appState: {}, files: {} } as never, null, null).elements as El[])[0].customData).toEqual({ learn });
    expect((newElementWith(shape as never, { strokeWidth: 4 } as never) as El).customData).toEqual({ learn });
    const normalized = JSON.parse(normalizeCanvasScene(JSON.stringify({ elements: [shape], appState: {}, files: {} }))) as { elements: El[] };
    expect(normalized.elements[0].customData).toEqual({ learn });
  });
});
