import { describe, expect, it } from "vitest";
import { PROJECT_MASCOTS } from "../../projects/model/projectMascots";
import {
  AGENT_AVATARS,
  AVATAR_BOX,
  agentAvatar,
  defaultAgentName,
} from "./agentAvatars";

describe("agentAvatars", () => {
  it("gives every avatar a closed shape and eyes inside the box", () => {
    expect(AGENT_AVATARS).toHaveLength(10);
    expect(new Set(AGENT_AVATARS.map((avatar) => avatar.body)).size).toBe(10);
    for (const avatar of AGENT_AVATARS) {
      expect(avatar.body).toMatch(/^M[\d. ]/);
      expect(avatar.body.endsWith("z")).toBe(true);
      const [x, y] = avatar.eyes;
      // Both eyes, each a short stroke, stay well within the shape's box.
      expect(x).toBeGreaterThan(4);
      expect(x + 3.8).toBeLessThan(AVATAR_BOX - 4);
      expect(y).toBeGreaterThan(4);
      expect(y + 2.8).toBeLessThan(AVATAR_BOX - 4);
    }
  });

  it("shares no name with a project mascot", () => {
    const mascots = new Set(PROJECT_MASCOTS.map((mascot) => mascot.name));
    for (const avatar of AGENT_AVATARS) {
      expect(mascots.has(avatar.name)).toBe(false);
    }
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
