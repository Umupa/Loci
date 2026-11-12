vi.mock("../../../integrations/harness/core/registry", () => ({
  getHarness: (id: string) =>
    id === "claude" || id === "codex"
      ? {
          commands: {
            discover: async () => [],
            rawSlashCommands: id === "codex",
          },
        }
      : undefined,
}));

import { describe, expect, it, vi } from "vitest";
import {
  isNativeCommandPrompt,
  rankSkills,
  replaceSlashToken,
  skillTextParts,
  slashTokenAt,
  type Skill,
} from "./skills";

describe("native command composer behavior", () => {
  it("filters commands by alias and inserts their invocation with arguments intact", () => {
    const workflow: Skill = {
      kind: "native",
      source: "codex",
      name: "workflow",
      invocation: "workflow",
      description: "Choose a workflow",
      aliases: ["review"],
    };
    expect(rankSkills([workflow], "review")).toEqual([workflow]);
    const text = "/rev foo";
    expect(
      replaceSlashToken(
        text,
        slashTokenAt(text, 4, true)!,
        workflow.invocation,
      ),
    ).toBe("/workflow foo");
    expect(slashTokenAt("/Review_Code", 12, true)?.query).toBe("Review_Code");
    expect(slashTokenAt("/Review_Code", 12)).toBeNull();
  });

  it("only treats leading command tokens as native invocations", () => {
    expect(isNativeCommandPrompt("/workflow foo @README.md", "codex")).toBe(true);
    expect(isNativeCommandPrompt("/codex:plan investigate", "codex")).toBe(true);
    for (const text of [
      "Explain /workflow",
      "> /workflow",
      "/tmp/file.ts",
      "/tmp\\file.ts",
      "hello",
    ]) {
      expect(isNativeCommandPrompt(text, "codex")).toBe(false);
    }
    expect(isNativeCommandPrompt("/review foo", "claude")).toBe(false);
  });
});

const review: Skill = {
  kind: "native",
  name: "review-pr",
  description: "Review pull requests against team standards.",
  invocation: "review-pr",
  source: "claude",
};

const compact: Skill = {
  kind: "builtin",
  name: "compact",
  description: "Summarize the conversation so far",
  invocation: "compact",
  scope: "builtin",
  source: "loci",
};

const providerNative: Skill = {
  kind: "native",
  name: "architect",
  description: "Design before implementation.",
  invocation: "skill:architect",
  source: "claude",
};


describe("slashTokenAt", () => {
  it("reads the /token the cursor is in", () => {
    expect(slashTokenAt("/cre", 4)).toEqual({
      start: 0,
      end: 4,
      query: "cre",
    });
    expect(slashTokenAt("please /rev", 11)).toEqual({
      start: 7,
      end: 11,
      query: "rev",
    });
    expect(slashTokenAt("/skill:arch", 11)).toEqual({
      start: 0,
      end: 11,
      query: "skill:arch",
    });
  });

  it("ignores URLs and paths", () => {
    expect(slashTokenAt("https://example.com", 12)).toBeNull();
    expect(slashTokenAt("/Users/me", 4)).toBeNull();
    expect(slashTokenAt("foo/bar", 4)).toBeNull();
  });

  it("closes after a space", () => {
    expect(slashTokenAt("/review-pr now", 14)).toBeNull();
  });
});

describe("replaceSlashToken", () => {
  it("inserts an exact invocation and a trailing space", () => {
    expect(
      replaceSlashToken(
        "/cre",
        { start: 0, end: 4, query: "cre" },
        "create-skill",
      ),
    ).toBe("/create-skill ");
    expect(
      replaceSlashToken(
        "x /r y",
        { start: 2, end: 4, query: "r" },
        "review-pr",
      ),
    ).toBe("x /review-pr y");
    expect(
      replaceSlashToken(
        "/arch",
        { start: 0, end: 5, query: "arch" },
        "skill:architect",
      ),
    ).toBe("/skill:architect ");
  });
});

describe("skillTextParts", () => {
  const names = new Set(["review-pr", "create-skill", "skill:architect"]);

  it("marks known /skill tokens", () => {
    expect(skillTextParts("/review-pr look at auth", names)).toEqual([
      { text: "/review-pr", skill: true },
      { text: " look at auth", skill: false },
    ]);
  });

  it("marks a known namespaced invocation", () => {
    expect(skillTextParts("/skill:architect inspect this", names)).toEqual([
      { text: "/skill:architect", skill: true },
      { text: " inspect this", skill: false },
    ]);
  });

  it("leaves unknown /tokens as plain text", () => {
    expect(skillTextParts("see /not-a-skill please", names)).toEqual([
      { text: "see /not-a-skill please", skill: false },
    ]);
  });

  it("splits multiple skills", () => {
    expect(skillTextParts("/review-pr then /create-skill", names)).toEqual([
      { text: "/review-pr", skill: true },
      { text: " then ", skill: false },
      { text: "/create-skill", skill: true },
    ]);
  });

  it("ignores skill tokens inside Markdown blockquotes", () => {
    const text = "/review-pr\n> /create-skill\n  > /review-pr";
    expect(slashTokenAt(text, text.indexOf("/create-skill") + 3)).toBeNull();
    expect(
      skillTextParts(text, names)
        .filter((part) => part.skill)
        .map((part) => part.text),
    ).toEqual(["/review-pr"]);
  });
});

describe("rankSkills", () => {
  it("puts Loci's own commands first when the query is empty", () => {
    const ranked = rankSkills([review, providerNative, compact], "");
    expect(ranked.map((s) => s.name)).toEqual(["compact", "architect", "review-pr"]);
  });

  it("fuzzy-matches names ahead of descriptions", () => {
    const ranked = rankSkills([providerNative, review, compact], "rev");
    expect(ranked[0]?.name).toBe("review-pr");
  });

  it("matches the displayed invocation", () => {
    expect(rankSkills([review, providerNative], "skill")).toEqual([providerNative]);
    expect(rankSkills([review, providerNative], "skill:arch")).toEqual([providerNative]);
  });

  it("keeps every provider result when the composer removes the default cap", () => {
    const rows: Skill[] = Array.from({ length: 75 }, (_, index) => ({
      kind: "native",
      name: `skill-${String(index).padStart(2, "0")}`,
      description: "provider skill",
      invocation: `skill:skill-${String(index).padStart(2, "0")}`,
      source: "claude",
    }));

    expect(rankSkills(rows, "")).toHaveLength(50);
    expect(rankSkills(rows, "", Number.POSITIVE_INFINITY)).toHaveLength(75);
    expect(
      rankSkills(rows, "skill-74", Number.POSITIVE_INFINITY)[0]?.name,
    ).toBe("skill-74");
  });
});
