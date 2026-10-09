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
  it("keeps every face on the mascots' grid, each with its own head and two eyes", () => {
    expect(AGENT_AVATARS).toHaveLength(10);
    expect(new Set(AGENT_AVATARS.map((avatar) => avatar.headPath)).size).toBe(10);
    for (const avatar of AGENT_AVATARS) {
      expect(avatar.rows).toHaveLength(AVATAR_GRID);
      for (const row of avatar.rows) {
        expect(row).toMatch(new RegExp(`^[#o.]{${AVATAR_GRID}}$`));
      }
      // Two eyes, two cells tall, side by side.
      const eyes = avatar.rows.filter((row) => row.includes("o"));
      expect(eyes).toHaveLength(2);
      expect(eyes[0]).toBe(eyes[1]);
      expect(eyes[0].split("o")).toHaveLength(3);
    }
  });

  it("shares no name with a project mascot", () => {
    const mascots = new Set(PROJECT_MASCOTS.map((mascot) => mascot.name));
    for (const avatar of AGENT_AVATARS) {
      expect(mascots.has(avatar.name)).toBe(false);
    }
  });

  it("merges the chosen cells' runs into one rect each", () => {
    expect(avatarPath(["##o##o.#"], "#o")).toBe("M0 0h6v1h-6zM7 0h1v1h-1z");
    expect(avatarPath(["##o##o.#"], "o")).toBe("M2 0h1v1h-1zM5 0h1v1h-1z");
    expect(avatarPath(["........"], "#o")).toBe("");
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
