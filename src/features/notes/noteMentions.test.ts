import { describe, expect, it } from "vitest";
import type { ProjectFile } from "../../platform/tauri/fs";
import { buildMentionIndex, fileMentionParts, mentionLabel, mentionTokenAt, replaceMentionToken, } from "./noteMentions";
const files: ProjectFile[] = [
    {
        name: "App.tsx",
        path: "/p/apps/desktop/src/App.tsx",
        relative: "apps/desktop/src/App.tsx",
    },
    {
        name: "App.tsx",
        path: "/p/apps/web/src/App.tsx",
        relative: "apps/web/src/App.tsx",
    },
    {
        name: "Composer.tsx",
        path: "/p/src/chrome/Composer.tsx",
        relative: "src/chrome/Composer.tsx",
    },
    {
        name: "read me.md",
        path: "/p/docs/read me.md",
        relative: "docs/read me.md",
    },
];
const index = buildMentionIndex(files);
describe("mentionTokenAt", () => {
    it("reads the @token the cursor is in", () => {
        expect(mentionTokenAt("@Comp", 5)).toEqual({
            start: 0,
            end: 5,
            query: "Comp",
        });
        expect(mentionTokenAt("look at @src/App", 16)).toEqual({
            start: 8,
            end: 16,
            query: "src/App",
        });
    });
    it("ignores emails and mid-word @", () => {
        expect(mentionTokenAt("nick@example.com", 8)).toBeNull();
        expect(mentionTokenAt("a@b", 3)).toBeNull();
    });
    it("closes after a space", () => {
        expect(mentionTokenAt("@App.tsx now", 12)).toBeNull();
    });
});
describe("replaceMentionToken", () => {
    it("inserts @label and a trailing space", () => {
        expect(replaceMentionToken("@Comp", { start: 0, end: 5, query: "Comp" }, "Composer.tsx")).toBe("@Composer.tsx ");
        expect(replaceMentionToken("x @a y", { start: 2, end: 4, query: "a" }, "App.tsx")).toBe("x @App.tsx y");
    });
});
describe("buildMentionIndex", () => {
    it("labels unique basenames short and ambiguous ones by path", () => {
        expect(mentionLabel(files[2], index)).toBe("Composer.tsx");
        expect(mentionLabel(files[0], index)).toBe("apps/desktop/src/App.tsx");
    });
    it("keeps a spaced path as a single @ token", () => {
        expect(mentionLabel(files[3], index)).toBe("docs/read-me.md");
        expect(index.labels.get("docs/read-me.md")).toBe(files[3]);
        expect(index.labels.has("read me.md")).toBe(false);
    });
    it("does not steal a token already owned by a real path", () => {
        const spaced: ProjectFile = {
            name: "read me.md",
            path: "/p/notes/read me.md",
            relative: "notes/read me.md",
        };
        const existing: ProjectFile = {
            name: "read-me.md",
            path: "/p/notes/read-me.md",
            relative: "notes/read-me.md",
        };
        const mixed = buildMentionIndex([spaced, existing]);
        expect(mentionLabel(existing, mixed)).toBe("read-me.md");
        expect(mixed.labels.get("notes/read-me.md")).toBe(existing);
        expect(mentionLabel(spaced, mixed)).toBe("notes/read-me.md~2");
        expect(mixed.labels.get("notes/read-me.md~2")).toBe(spaced);
    });
    it("ignores paths that leave the project or break the tokenizer", () => {
        const unsafe = buildMentionIndex([
            { name: "secret", path: "/etc/secret", relative: "../secret" },
            { name: "abs", path: "/tmp/abs", relative: "/tmp/abs" },
            { name: "at.md", path: "/p/at.md", relative: "see@me.md" },
            { name: "nul", path: "/p/nul", relative: "bad\0name.md" },
            { name: "ls.md", path: "/p/ls.md", relative: "docs/read\u2028me.md" },
            { name: "ps.md", path: "/p/ps.md", relative: "docs/read\u2029me.md" },
            { name: "nel.md", path: "/p/nel.md", relative: "a\u0085b.md" },
            { name: "bidi.md", path: "/p/bidi.md", relative: "photo\u202Egpj.md" },
            { name: "zwsp.ts", path: "/p/zwsp.ts", relative: "file\u200B.ts" },
        ]);
        expect(unsafe.labels.size).toBe(0);
    });
    it("always accepts the relative path as a label", () => {
        expect(index.labels.get("apps/web/src/App.tsx")).toBe(files[1]);
        expect(index.labels.get("src/chrome/Composer.tsx")).toBe(files[2]);
    });
});
describe("fileMentionParts", () => {
    it("splits known mentions out of the surrounding text", () => {
        expect(fileMentionParts("fix @Composer.tsx now", index.labels)).toEqual([
            { text: "fix " },
            { text: "@Composer.tsx", file: files[2] },
            { text: " now" },
        ]);
    });
    it("leaves unknown mentions and emails alone", () => {
        expect(fileMentionParts("ping @nobody.tsx", index.labels)).toEqual([
            { text: "ping @nobody.tsx" },
        ]);
        expect(fileMentionParts("nick@example.com", index.labels)).toEqual([
            { text: "nick@example.com" },
        ]);
    });
    it("keeps trailing punctuation outside the mention", () => {
        expect(fileMentionParts("see @Composer.tsx, then", index.labels)).toEqual([
            { text: "see " },
            { text: "@Composer.tsx", file: files[2] },
            { text: ", then" },
        ]);
    });
    it("ignores file mentions inside Markdown blockquotes", () => {
        const text = "@Composer.tsx\n> @apps/web/src/App.tsx";
        expect(mentionTokenAt(text, text.indexOf("@apps/web") + 4)).toBeNull();
        expect(fileMentionParts(text, index.labels).filter((part) => part.file)).toHaveLength(1);
    });
});
