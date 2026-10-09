// @vitest-environment happy-dom
import { beforeEach, expect, it } from "vitest";
import {
  AGENT_TEMPLATES,
  agentTemplate,
  agentTemplateEdited,
  listAgentTemplates,
  resetAgentTemplate,
  saveAgentTemplate,
  templateSoul,
} from "./agentTemplates";

beforeEach(() => localStorage.clear());

it("uses the user's wording for a template and goes back to what ships", () => {
  const shipped = AGENT_TEMPLATES.find((template) => template.id === "tutor")!;
  saveAgentTemplate("tutor", { ...shipped, soul: "- Teach by asking.", name: "  Mentor " });
  const edited = agentTemplate("tutor")!;
  expect(edited.soul).toBe("- Teach by asking.");
  expect(edited.name).toBe("Mentor");
  // What was left as shipped follows later changes to the shipped text.
  expect(edited.ask).toBe(shipped.ask);
  expect(JSON.parse(localStorage.getItem("loci:agent-template-edits")!)).toEqual({
    tutor: { soul: "- Teach by asking.", name: "  Mentor " },
  });
  expect(templateSoul(edited)).toContain("- Teach by asking.");
  expect(agentTemplateEdited("tutor")).toBe(true);
  expect(agentTemplateEdited("reviewer")).toBe(false);

  resetAgentTemplate("tutor");
  expect(agentTemplate("tutor")).toEqual(shipped);
  expect(agentTemplateEdited("tutor")).toBe(false);
});

it("keeps the shipped text for a field left empty, except a habit, which may be removed", () => {
  const shipped = AGENT_TEMPLATES.find((template) => template.id === "project-lead")!;
  saveAgentTemplate("project-lead", { ...shipped, soul: "   ", habit: "" });
  const edited = agentTemplate("project-lead")!;
  expect(edited.soul).toBe(shipped.soul);
  expect(edited.habit).toBeUndefined();
});

it("saving a template unchanged leaves nothing behind, and broken storage is ignored", () => {
  const shipped = AGENT_TEMPLATES[0];
  saveAgentTemplate(shipped.id, { ...shipped });
  expect(agentTemplateEdited(shipped.id)).toBe(false);
  localStorage.setItem("loci:agent-template-edits", "not json");
  expect(listAgentTemplates()).toEqual(AGENT_TEMPLATES);
});
