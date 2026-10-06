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
  BUILTIN_CREATE_SKILL,
  applySkillsToTurn,
  blankSkillMarkdown,
  injectSkillPrompt,
  isValidSkillName,
  isNativeCommandPrompt,
  mergeCatalog,
  rankSkills,
  replaceSlashToken,
  skillNamesInText,
  skillTextParts,
  slashTokenAt,
  slugSkillName,
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
  kind: "file",
  name: "review-pr",
  description: "Review pull requests against team standards.",
  invocation: "review-pr",
  path: "/tmp/.agents/skills/review-pr/SKILL.md",
  scope: "project",
  source: "agents",
};

const native: Skill = {
  kind: "file",
  name: "claude-only",
  description: "Claude helper",
  invocation: "claude-only",
  path: "/tmp/.claude/skills/claude-only/SKILL.md",
  scope: "project",
  source: "claude",
};

const providerNative: Skill = {
  kind: "native",
  name: "architect",
  description: "Design before implementation.",
  invocation: "skill:architect",
  source: "claude",
};

const providerFile: Skill = {
  kind: "file",
  name: "provider-file",
  description: "A file discovered by the existing scanner.",
  invocation: "provider-file",
  path: "/tmp/.claude/skills/provider-file/SKILL.md",
  scope: "project",
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

describe("skillNamesInText", () => {
  it("collects unique /skill tokens", () => {
    expect(skillNamesInText("/create-skill write a deploy skill")).toEqual([
      "create-skill",
    ]);
    expect(skillNamesInText("/review-pr /create-skill /review-pr")).toEqual([
      "review-pr",
      "create-skill",
    ]);
    expect(skillNamesInText("path /tmp/foo")).toEqual([]);
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
    expect(skillNamesInText(text)).toEqual(["review-pr"]);
    expect(
      skillTextParts(text, names)
        .filter((part) => part.skill)
        .map((part) => part.text),
    ).toEqual(["/review-pr"]);
  });
});

describe("applySkillsToTurn", () => {
  it("leaves provider-native skill commands unchanged", async () => {
    await expect(
      applySkillsToTurn("/skill:architect inspect this", {
        harness: "claude",
        cwd: "/repo",
      }),
    ).resolves.toBe("/skill:architect inspect this");
  });
});

describe("injectSkillPrompt", () => {
  it("prefixes invoked skill bodies and keeps the user text", () => {
    const out = injectSkillPrompt("/review-pr look at auth", [review], {
      "review-pr": "# Review\n\nBe strict.",
    });
    expect(out).toContain("## /review-pr");
    expect(out).toContain("Be strict.");
    expect(out.endsWith("/review-pr look at auth")).toBe(true);
  });

  it("returns the original text when nothing matches", () => {
    expect(injectSkillPrompt("hello", [], {})).toBe("hello");
  });
});

describe("mergeCatalog", () => {
  it("lets .agents win, then Loci create-skill, then provider skills", () => {
    const catalog = mergeCatalog([
      {
        name: "review-pr",
        description: "from agents",
        path: "/p/.agents/skills/review-pr/SKILL.md",
        scope: "project",
        source: "agents",
      },
      {
        name: "review-pr",
        description: "from claude",
        path: "/p/.claude/skills/review-pr/SKILL.md",
        scope: "project",
        source: "claude",
      },
      {
        name: "create-skill",
        description: "claude native",
        path: "/home/.claude/skills/create-skill/SKILL.md",
        scope: "user",
        source: "claude",
      },
      {
        name: "claude-only",
        description: "native",
        path: "/p/.claude/skills/claude-only/SKILL.md",
        scope: "project",
        source: "claude",
      },
    ]);
    expect(catalog.find((s) => s.name === "review-pr")?.description).toBe(
      "from agents",
    );
    expect(catalog.find((s) => s.name === "create-skill")).toEqual(
      BUILTIN_CREATE_SKILL,
    );
    expect(catalog.find((s) => s.name === "claude-only")?.source).toBe(
      "claude",
    );
  });
});

describe("rankSkills", () => {
  it("puts create-skill first when the query is empty", () => {
    const ranked = rankSkills([native, review, BUILTIN_CREATE_SKILL], "");
    expect(ranked.map((s) => s.name)).toEqual([
      "create-skill",
      "claude-only",
      "review-pr",
    ]);
  });

  it("fuzzy-matches names ahead of descriptions", () => {
    const ranked = rankSkills([native, review, BUILTIN_CREATE_SKILL], "rev");
    expect(ranked[0]?.name).toBe("review-pr");
  });

  it("ranks native provider rows with project skills", () => {
    const ranked = rankSkills([review, providerNative, providerFile], "");
    expect(ranked.map((skill) => skill.name)).toEqual([
      "architect",
      "provider-file",
      "review-pr",
    ]);
  });

  it("matches the displayed invocation", () => {
    expect(rankSkills([review, providerNative], "skill")).toEqual([providerNative]);
    expect(rankSkills([review, providerNative], "skill:arch")).toEqual([providerNative]);
  });

  it("gives the built-in row its exact invocation", () => {
    expect(BUILTIN_CREATE_SKILL.invocation).toBe("create-skill");
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

describe("skill names", () => {
  it("slugs and validates", () => {
    expect(slugSkillName("Review PR")).toBe("review-pr");
    expect(isValidSkillName("review-pr")).toBe(true);
    expect(isValidSkillName("Review")).toBe(false);
    expect(isValidSkillName("-nope")).toBe(false);
  });

  it("writes a starter SKILL.md", () => {
    const md = blankSkillMarkdown("review-pr");
    expect(md).toContain("name: review-pr");
    expect(md).toContain("# Review Pr");
  });
});
