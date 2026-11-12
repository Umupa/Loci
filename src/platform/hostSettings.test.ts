// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { applyHostSettings, HOST_SHARED_KEYS, hostSettingsSnapshot, onHostSettingApplied, setHostSettingSink } from "./hostSettings";
import { saveNewAgentAccess } from "../features/agents/model/agentAccess";
import { saveLearningLanguage } from "../features/agents/model/learningLanguage";
import {
  saveDefaultModel, saveLastModelChoice, saveLastModelSettings, savePickerProviderVisible,
} from "../features/sessions/model/models";
import { setProjectDefaultProvider } from "../features/sessions/model/projectProviders";
import { saveProviderBinaryPath } from "../features/providers/model/providerBinaryPaths";
import { saveClaudeHooks, saveFollowUpBehavior } from "../features/settings/model/settings";
import { archiveProject, rememberProject } from "../features/projects/model/recents";

beforeEach(() => localStorage.clear());
afterEach(() => setHostSettingSink(undefined));

describe("host settings", () => {
  it("has a writer for every shared key that tells the host, or the window's host, about it", () => {
    const written = new Set<string>();
    setHostSettingSink((key) => written.add(key));
    saveNewAgentAccess("auto");
    saveLearningLanguage("en");
    saveLastModelSettings({ effort: "high" });
    savePickerProviderVisible("pi", false);
    saveDefaultModel("claude", "claude:sonnet");
    saveLastModelChoice("codex", "codex:test");
    setProjectDefaultProvider("/w", "codex");
    saveProviderBinaryPath("claude", "/opt/claude");
    saveFollowUpBehavior("queue");
    saveClaudeHooks(false);
    rememberProject("/w");
    archiveProject("/w");
    // Accounts are only read so far; whatever writes them later joins this list.
    const readOnly = ["loci.providerAccounts.v1", "loci.providerAccountSelections.v1"];
    expect([...written].sort()).toEqual(HOST_SHARED_KEYS.filter((key) => !readOnly.includes(key)).sort());
  });

  it("stores the other side's values and tells readers as another window's write would", () => {
    const storage = vi.fn();
    const refresh = vi.fn();
    window.addEventListener("storage", storage);
    onHostSettingApplied("loci.claudeHooks", refresh);
    localStorage.setItem("loci.followUpBehavior", "steer");
    applyHostSettings({ "loci.followUpBehavior": "queue", "loci.claudeHooks": "[]", "loci:agent-handed": "{}", "loci.theme": "dark" });
    expect(localStorage.getItem("loci.followUpBehavior")).toBe("queue");
    expect(localStorage.getItem("loci:agent-handed")).toBeNull();
    expect(localStorage.getItem("loci.theme")).toBeNull();
    expect(storage.mock.calls.map(([event]) => [event.key, event.oldValue, event.newValue])).toEqual([
      ["loci.followUpBehavior", "steer", "queue"], ["loci.claudeHooks", null, "[]"],
    ]);
    expect(refresh).toHaveBeenCalledOnce();
    applyHostSettings({ "loci.followUpBehavior": null });
    expect(localStorage.getItem("loci.followUpBehavior")).toBeNull();
    window.removeEventListener("storage", storage);
  });

  it("reads every shared key and nothing else", () => {
    localStorage.setItem("loci.followUpBehavior", "queue");
    localStorage.setItem("loci.theme", "dark");
    const snapshot = hostSettingsSnapshot();
    expect(Object.keys(snapshot)).toEqual(HOST_SHARED_KEYS);
    expect(snapshot["loci.followUpBehavior"]).toBe("queue");
    expect(snapshot["loci.lastModel"]).toBeNull();
  });
});
