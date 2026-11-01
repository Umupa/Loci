// @vitest-environment happy-dom
import { describe, expect, it } from "vitest";
import {
  AGENT_AVATARS,
  agentAvatar,
  defaultAgentName,
} from "./agentAvatars";

const SAVED_NAMES = ["ember", "wisp", "dew", "moss", "nimbus", "pebble", "luna", "nova", "flint", "tide"];

describe("agentAvatars", () => {
  it("keeps every name agents saved with the earlier faces, each a distinct face", () => {
    const names = AGENT_AVATARS.map((avatar) => avatar.name);
    expect(names.slice(0, SAVED_NAMES.length)).toEqual(SAVED_NAMES);
    expect(new Set(names).size).toBe(names.length);
    expect(new Set(AGENT_AVATARS.map((avatar) => avatar.markup)).size).toBe(AGENT_AVATARS.length);
    for (const avatar of AGENT_AVATARS) {
      expect(avatar.style).toBe("notionists");
      expect(avatar.viewBox).not.toBe(avatar.faceViewBox);
    }
  });

  it("embeds local artwork on a card that follows the agent's color", () => {
    for (const avatar of AGENT_AVATARS) {
      expect(avatar.markup).toContain('fill="currentColor"');
      expect(avatar.markup).not.toMatch(/<(?:script|foreignObject|image|filter)\b/i);
      expect(avatar.markup).not.toMatch(/\bon\w+\s*=|(?:https?:|data:|javascript:)/i);
      for (const [, href] of avatar.markup.matchAll(/\bhref="([^"]+)"/g)) {
        expect(href).toMatch(/^#__LOCI_AVATAR_ID__-/);
      }
    }
  });

  it.each(AGENT_AVATARS)("keeps $name's eyes in one blinkable group in the rendered SVG tree", ({ markup, canBlink }) => {
    expect(canBlink).toBe(true);
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.innerHTML = markup;
    const eyes = svg.querySelectorAll("g.agent-avatar-eyes");
    expect(eyes).toHaveLength(1);
    expect(eyes[0].closest("defs")).toBeNull();
  });

  it("wears the same face for an earlier neutral name, and the first face for an unknown one", () => {
    expect(agentAvatar("dew").name).toBe("dew");
    expect(agentAvatar("neutral-dew").name).toBe("dew");
    expect(agentAvatar("nope")).toBe(AGENT_AVATARS[0]);
    expect(agentAvatar(null)).toBe(AGENT_AVATARS[0]);
  });

  it("names an agent after its avatar until the user names it", () => {
    expect(defaultAgentName("ember")).toBe("Ember");
    expect(defaultAgentName("neutral-tide")).toBe("Tide");
    expect(defaultAgentName("nope")).toBe("Ember");
  });
});
