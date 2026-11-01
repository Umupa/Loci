// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { languageFromFile } from "../lib/markdown/codeLanguage";
import { lineOffset } from "../../features/files/model/filePlace";
import { linesOf, rangeAt, textIndex } from "../../features/learning/model/textAnchor";
import { excerptLines } from "../../features/learning/ui/CoursePane";
import { CodeReader } from "./CodeReader";

const highlighter = vi.hoisted(() => ({
    highlight: vi.fn(({ code }: { code: string }) => ({
        tokens: code.split("\n").map((line) => [{ content: line, htmlStyle: { color: "#24292e", "--shiki-dark": "#e1e4e8" } }]),
    })),
    getThemes: () => ["github-light", "github-dark"],
}));
const scheme = vi.hoisted(() => ({ value: "dark" as "dark" | "light" }));
vi.mock("../hooks/useCodePlugin", () => ({ useCodePlugin: () => highlighter }));
vi.mock("../hooks/useColorScheme", () => ({ useColorScheme: () => scheme.value }));

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
    vi.clearAllMocks();
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    container = document.createElement("div");
    document.body.append(container);
    root = createRoot(container);
});

afterEach(() => {
    act(() => root.unmount());
    container.remove();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
});

it("reads a file's language from its extension or bare name", () => {
    expect(languageFromFile("/src/main.rs")).toBe("rust");
    expect(languageFromFile("App.tsx")).toBe("tsx");
    expect(languageFromFile("Dockerfile")).toBe("dockerfile");
    expect(languageFromFile("Makefile")).toBe("makefile");
    expect(languageFromFile("notes.txt")).toBe("txt");
});

it("numbers every line from the excerpt's first line and keeps the text exact", async () => {
    const text = "fn main() {\n    run();\n}";
    await act(async () => root.render(createElement(CodeReader, { text, file: "/src/main.rs", firstLine: 12 })));

    const reader = container.querySelector<HTMLElement>("[data-code-reader]")!;
    expect(reader.querySelector("pre code")?.textContent).toBe(text);
    expect([...reader.querySelectorAll(".code-reader__number")].map((number) => number.textContent)).toEqual(["12", "13", "14"]);
    expect(highlighter.highlight).toHaveBeenCalledWith(expect.objectContaining({ code: text, language: "rust" }), expect.any(Function));
});

it("keeps the gutter out of the reading text, so anchors and line links land on the right line", async () => {
    const text = "alpha\nbeta\ngamma";
    await act(async () => root.render(createElement(CodeReader, { text, file: "notes.txt", firstLine: 1 })));

    const reader = container.querySelector<HTMLElement>("[data-code-reader]")!;
    const index = textIndex(reader);
    expect(index.text).toBe(text);

    const at = index.text.indexOf("beta");
    const range = rangeAt(index, at, at + "beta".length)!;
    expect(excerptLines(range, 1)).toEqual([2, 2]);
});

it("turns a line link into a caret on that line of the highlighted file", async () => {
    const text = Array.from({ length: 40 }, (_, index) => `line ${index + 1}`).join("\n");
    await act(async () => root.render(createElement(CodeReader, { text, file: "main.rs", firstLine: 1 })));

    const reader = container.querySelector<HTMLElement>("[data-code-reader]")!;
    const index = textIndex(reader);
    const at = lineOffset(text, 12);
    const caret = rangeAt(index, at, at + 1)!;
    const before = document.createRange();
    before.selectNodeContents(reader.querySelector("code")!);
    before.setEnd(caret.startContainer, caret.startOffset);
    expect(linesOf(index.text, before.toString().length, at)).toEqual([12, 12]);
    expect(reader.querySelectorAll(".code-reader__number")[11].textContent).toBe("12");
});

it("uses the readable half of the Shiki theme pair in each color scheme", async () => {
    scheme.value = "dark";
    await act(async () => root.render(createElement(CodeReader, { text: "let x = 1;", file: "a.ts" })));
    expect(container.querySelector<HTMLElement>("pre code > span")?.style.color).toBe("#e1e4e8");

    scheme.value = "light";
    await act(async () => root.render(createElement(CodeReader, { text: "let y = 2;", file: "b.ts" })));
    const light = [...container.querySelectorAll<HTMLElement>("pre code > span")].map((span) => span.style.color);
    expect(light[0]).toBe("#24292e");
});

it("shows the text unhighlighted while tokens are on their way", async () => {
    highlighter.highlight.mockReturnValueOnce(null as never);
    await act(async () => root.render(createElement(CodeReader, { text: "one\ntwo", file: "a.py" })));
    expect(container.querySelector("pre code")?.textContent).toBe("one\ntwo");
});
