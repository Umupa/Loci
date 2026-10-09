import { describe, expect, it } from "vitest";
import { PROJECT_MASCOTS } from "../../projects/model/projectMascots";
import {
  AGENT_AVATARS,
  AVATAR_GRID,
  agentAvatar,
  avatarPath,
  defaultAgentName,
} from "./agentAvatars";

describe("agentAvatars", () => {
  it("keeps every avatar on the shared grid with an inked, filled figure", () => {
    expect(AGENT_AVATARS).toHaveLength(10);
    for (const avatar of AGENT_AVATARS) {
      expect(avatar.rows).toHaveLength(AVATAR_GRID);
      for (const row of avatar.rows) {
        expect(row).toMatch(new RegExp(`^[#o+.]{${AVATAR_GRID}}$`));
      }
      expect(avatar.inkPath).not.toBe("");
      expect(avatar.fillPath).not.toBe("");
    }
  });

  it("shares no name with a project mascot", () => {
    const mascots = new Set(PROJECT_MASCOTS.map((mascot) => mascot.name));
    for (const avatar of AGENT_AVATARS) {
      expect(mascots.has(avatar.name)).toBe(false);
    }
  });

  it("merges one tone's runs into rects inside the frame", () => {
    expect(avatarPath(["##.oo+###."], "#")).toBe("M1 1h2v1h-2zM7 1h3v1h-3z");
    expect(avatarPath(["##.oo+###."], "o")).toBe("M4 1h2v1h-2z");
    expect(avatarPath([".........."], "#")).toBe("");
  });

  it("falls back to the first avatar for an unknown name", () => {
    expect(agentAvatar("dew").name).toBe("dew");
    expect(agentAvatar("nope")).toBe(AGENT_AVATARS[0]);
    expect(agentAvatar(null)).toBe(AGENT_AVATARS[0]);
  });

  it("names an agent after its avatar until the user names it", () => {
    expect(defaultAgentName("ember")).toBe("Ember");
    expect(defaultAgentName("nope")).toBe("Ember");
  });
});
