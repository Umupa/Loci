import { describe,expect,it } from "vitest";
import {
buildThreadTitlePrompt,
parseGeneratedSessionTitle,
shouldGenerateSessionTitle
} from "./sessionTitle";

describe("session title metadata", () => {
  it("requests one concise title for the conversation", () => {
    const prompt = buildThreadTitlePrompt("Compare the survey results");
    expect(prompt).toContain("Return JSON with exactly one key: title.");
    expect(prompt).toContain("Compare the survey results");
    expect(prompt).toContain("Do not call tools.");
  });

  it("accepts a generated JSON title", () => {
    expect(parseGeneratedSessionTitle('{"title":"Compare survey results"}')).toEqual({ title: "Compare survey results" });
  });

  it("keeps compatibility with a bare generated title", () => {
    expect(parseGeneratedSessionTitle("Fix session links")).toEqual(
      { title: "Fix session links" },
    );
  });

  it("can refresh a generated title for an event added to an existing session", () => {
    expect(shouldGenerateSessionTitle(false, false, true)).toBe(true);
    expect(shouldGenerateSessionTitle(false, false)).toBe(false);
    expect(shouldGenerateSessionTitle(true, true)).toBe(true);
  });
});
