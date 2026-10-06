vi.mock("../../../integrations/harness/core/registry", () => ({
  getHarness: (id: string) =>
    id === "codex"
      ? {
          commands: {
            discover: async () => [],
            rawSlashCommands: id === "codex",
          },
        }
      : undefined,
}));

import { describe, expect, it, vi } from "vitest";
import type { Skill } from "../../skills/model/skills";
import {
  nextComposerSkillContextToken,
  pickerSkillLoadOptions,
  visibleComposerSkills,
} from "./useComposerSkills";

const nativeSkill: Skill = {
  kind: "native",
  name: "architect",
  description: "Design first.",
  invocation: "skill:architect",
  source: "codex",
};

const cachedSkill: Skill = {
  kind: "native",
  name: "cached",
  description: "Cached current context.",
  invocation: "skill:cached",
  source: "codex",
};

describe("composer skill catalog policies", () => {
  it("uses loaded rows only for their owning context", () => {
    expect(
      visibleComposerSkills(
        { key: "codex\0/a", skills: [nativeSkill] },
        "codex\0/a",
        null,
        [],
      ),
    ).toEqual([nativeSkill]);
    expect(
      visibleComposerSkills(
        { key: "codex\0/a", skills: [nativeSkill] },
        "codex\0/b",
        [cachedSkill],
        [],
      ),
    ).toEqual([cachedSkill]);
  });

  it("preserves filesystem refresh while a native catalog uses its TTL", () => {
    expect(pickerSkillLoadOptions("codex")).toBeUndefined();
    expect(pickerSkillLoadOptions("codex")).toBeUndefined();
    expect(pickerSkillLoadOptions("claude")).toEqual({ refresh: true });
  });

  it("does not reuse a context token after A to B to A", () => {
    const firstA = nextComposerSkillContextToken(null, "codex\0/a");
    const sameA = nextComposerSkillContextToken(firstA, "codex\0/a");
    const b = nextComposerSkillContextToken(sameA, "codex\0/b");
    const secondA = nextComposerSkillContextToken(b, "codex\0/a");

    expect(sameA).toBe(firstA);
    expect(secondA.key).toBe(firstA.key);
    expect(secondA).not.toBe(firstA);
    expect(secondA.generation).toBeGreaterThan(firstA.generation);
  });
});
