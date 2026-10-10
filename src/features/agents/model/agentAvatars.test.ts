// @vitest-environment happy-dom
import { describe, expect, it } from "vitest";
import { PROJECT_MASCOTS } from "../../projects/model/projectMascots";
import {
  AGENT_AVATARS,
  agentAvatar,
  defaultAgentName,
} from "./agentAvatars";

describe("agentAvatars", () => {
  it("keeps the persisted Bottts names and adds a matching Neutral series on its own canvas", () => {
    const bottts = AGENT_AVATARS.filter((avatar) => avatar.style === "bottts");
    const neutral = AGENT_AVATARS.filter((avatar) => avatar.style === "bottts-neutral");
    expect(bottts.map((avatar) => avatar.name)).toEqual([
      "ember",
      "wisp",
      "dew",
      "moss",
      "nimbus",
      "pebble",
      "luna",
      "nova",
      "flint",
      "tide",
    ]);
    expect(neutral.map((avatar) => avatar.name)).toEqual(bottts.map((avatar) => `neutral-${avatar.name}`));
    expect(AGENT_AVATARS).toHaveLength(20);
    for (const avatar of bottts) expect(avatar.viewBox).toBe("0 0 180 180");
    for (const avatar of neutral) expect(avatar.viewBox).toBe("0 0 120 120");
    expect(new Set(AGENT_AVATARS.map((avatar) => avatar.markup)).size).toBe(20);
  });

  it("embeds local artwork whose base color can follow the agent's color", () => {
    for (const avatar of AGENT_AVATARS) {
      expect(avatar.markup).toContain('fill="currentColor"');
      expect(avatar.markup).not.toMatch(/<(?:script|foreignObject|image|filter)\b/i);
      expect(avatar.markup).not.toMatch(/\bon\w+\s*=|(?:https?:|data:|javascript:)/i);
      for (const [, href] of avatar.markup.matchAll(/\bhref="([^"]+)"/g)) {
        expect(href).toMatch(/^#__LOCI_AVATAR_ID__-/);
      }
    }
  });

  it("only marks faces with animated eye artwork as able to blink", () => {
    for (const avatar of AGENT_AVATARS) {
      expect(avatar.canBlink).toBe(avatar.markup.includes('class="agent-avatar-eyes"'));
    }
    for (const name of ["ember", "wisp", "pebble", "neutral-ember", "neutral-wisp", "neutral-pebble"]) {
      expect(agentAvatar(name).canBlink).toBe(false);
    }
    expect(agentAvatar("dew").canBlink).toBe(true);
    expect(agentAvatar("neutral-dew").canBlink).toBe(true);
  });

  it.each(AGENT_AVATARS.filter((avatar) => avatar.canBlink))("keeps $name's animated eyes in the rendered SVG tree", ({ markup }) => {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.innerHTML = markup;
    const eyes = svg.querySelectorAll("g.agent-avatar-eyes");
    expect(eyes.length).toBeGreaterThan(0);
    // Animating an eye definition used by a clone does not repaint the visible eyes.
    for (const eye of eyes) expect(eye.closest("defs")).toBeNull();
  });

  it("shares no name with a project mascot", () => {
    const mascots = new Set(PROJECT_MASCOTS.map((mascot) => mascot.name));
    for (const avatar of AGENT_AVATARS) {
      expect(mascots.has(avatar.name)).toBe(false);
    }
  });

  it("falls back to the first avatar for an unknown name", () => {
    expect(agentAvatar("dew").name).toBe("dew");
    expect(agentAvatar("neutral-dew").name).toBe("neutral-dew");
    expect(agentAvatar("nope")).toBe(AGENT_AVATARS[0]);
    expect(agentAvatar(null)).toBe(AGENT_AVATARS[0]);
  });

  it("names an agent after its avatar until the user names it", () => {
    expect(defaultAgentName("ember")).toBe("Ember");
    expect(defaultAgentName("nope")).toBe("Ember");
    for (const avatar of AGENT_AVATARS.filter((avatar) => avatar.style === "bottts")) {
      expect(defaultAgentName(`neutral-${avatar.name}`)).toBe(defaultAgentName(avatar.name));
    }
  });
});
