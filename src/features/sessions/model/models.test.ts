import { afterEach,beforeEach,describe,expect,it } from "vitest";
import {
MODELS,
coerceModelPickerTab,
defaultModelId,
defaultSessionChoice,
encodeModelLaunchId,
firstEnabledHarness,
hasLiveCatalog,
isPickerProviderVisible,
loadDefaultModels,
loadHiddenPickerProviders,
loadLastModelChoice,
loadLastModelSettings,
loadRecentModelChoices,
mergeModelSettings,
modelPickerTabs,
nativeModelId,
preferredModelId,
preferredModelSettings,
resetHarnessModelOverlays,
resolveModel,
saveDefaultModel,
saveLastModelChoice,
saveLastModelSettings,
savePickerProviderVisible,
saveRecentModelChoice,
setHarnessModels,
showProviderInModelPicker,
stepModelPickerTab,
type AgentModel
} from "./models";
import {
setProjectDefaultProvider,
setProjectProviderHidden,
} from "./projectProviders";
import { newSession,type HarnessId } from "./session";

const opus: AgentModel = {
  id: "claude:opus-5",
  harness: "claude",
  name: "Opus 5",
  settings: [
    {
      id: "effort",
      label: "Reasoning",
      kind: "select",
      value: "high",
      options: [
        { value: "high", label: "High" },
        { value: "xhigh", label: "Extra High" },
        { value: "max", label: "Max" },
      ],
    },
    {
      id: "fast",
      label: "Fast",
      kind: "toggle",
      value: "false",
      options: [
        { value: "true", label: "On" },
        { value: "false", label: "Off" },
      ],
    },
  ],
};

const haiku: AgentModel = {
  id: "claude:haiku-4.5",
  harness: "claude",
  name: "Haiku 4.5",
  settings: [
    {
      id: "thinking",
      label: "Thinking",
      kind: "toggle",
      value: "false",
      options: [
        { value: "true", label: "On" },
        { value: "false", label: "Off" },
      ],
    },
  ],
};

function mockLocalStorage() {
  const data = new Map<string, string>();
  const storage = {
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => {
      data.set(key, value);
    },
    removeItem: (key: string) => {
      data.delete(key);
    },
    clear: () => {
      data.clear();
    },
    key: (index: number) => [...data.keys()][index] ?? null,
    get length() {
      return data.size;
    },
  };
  Object.defineProperty(globalThis, "localStorage", {
    value: storage,
    configurable: true,
  });
}

describe("model settings memory", () => {
  beforeEach(() => {
    mockLocalStorage();
  });

  afterEach(() => {
    mockLocalStorage();
  });

  it("keeps valid current values when merging onto a model", () => {
    expect(mergeModelSettings(opus, { effort: "xhigh", fast: "true" })).toEqual(
      { effort: "xhigh", fast: "true" },
    );
  });

  it("drops values the new model does not support", () => {
    expect(
      mergeModelSettings(haiku, { effort: "xhigh", fast: "true" }),
    ).toEqual({ thinking: "false" });
  });

  it("maps extra-high onto Claude's xhigh", () => {
    expect(mergeModelSettings(opus, { effort: "extra-high" })).toEqual({
      effort: "xhigh",
      fast: "false",
    });
  });

  it("remembers extra-high and fast across models that support them", () => {
    saveLastModelSettings({ effort: "xhigh", fast: "true" });
    expect(preferredModelSettings(opus)).toEqual({
      effort: "xhigh",
      fast: "true",
    });
    expect(preferredModelSettings(haiku)).toEqual({ thinking: "false" });
  });

  it("merges newly saved settings into previously stored ones", () => {
    saveLastModelSettings({ effort: "xhigh", fast: "true" });
    saveLastModelSettings({ thinking: "true" });
    expect(loadLastModelSettings()).toEqual({
      effort: "xhigh",
      fast: "true",
      thinking: "true",
    });
  });

  it("applies stored preferences over a session's current values", () => {
    saveLastModelSettings({ effort: "xhigh", fast: "true" });
    expect(
      preferredModelSettings(opus, { effort: "high", fast: "false" }),
    ).toEqual({
      effort: "xhigh",
      fast: "true",
    });
  });

  it("fill mode keeps stored preferences when the session still has defaults", () => {
    saveLastModelSettings({ effort: "xhigh", fast: "true" });
    saveLastModelSettings({ effort: "high", fast: "false" }, "fill");
    expect(loadLastModelSettings()).toEqual({
      effort: "xhigh",
      fast: "true",
    });
  });

  it("fill mode records session values that have not been stored yet", () => {
    saveLastModelSettings({ effort: "xhigh" }, "fill");
    expect(loadLastModelSettings()).toEqual({ effort: "xhigh" });
  });

  it("uses the current session when nothing has been stored yet", () => {
    expect(
      preferredModelSettings(opus, { effort: "xhigh", fast: "true" }),
    ).toEqual({ effort: "xhigh", fast: "true" });
  });
});

describe("provider defaults", () => {
  beforeEach(() => {
    mockLocalStorage();
  });

  afterEach(() => {
    mockLocalStorage();
  });

  it("remembers a model per provider without changing the default provider", () => {
    saveLastModelChoice("codex", "codex:gpt-5.4");
    saveDefaultModel("claude", "claude:opus-5");
    expect(loadLastModelChoice()).toEqual({
      harness: "codex",
      model: "codex:gpt-5.4",
    });
    expect(loadDefaultModels()).toEqual({
      codex: "codex:gpt-5.4",
      claude: "claude:opus-5",
    });
    expect(preferredModelId("claude")).toBe("claude:opus-5");
    expect(preferredModelId("codex")).toBe("codex:gpt-5.4");
  });

  it("falls back to lastModel for the default provider when no map exists", () => {
    localStorage.setItem(
      "loci.lastModel",
      JSON.stringify({ harness: "codex", model: "codex:gpt-5.4" }),
    );
    expect(preferredModelId("codex")).toBe("codex:gpt-5.4");
    expect(preferredModelId("claude")).toBe(defaultModelId("claude"));
  });

  it("uses the saved default provider and its model for new sessions", () => {
    saveLastModelChoice("claude", "claude:opus-5");
    expect(defaultSessionChoice()).toEqual({
      harness: "claude",
      model: "claude:opus-5",
    });
  });

  it("keeps catalog defaults when nothing is saved", () => {
    expect(defaultSessionChoice()).toEqual({ harness: "claude", model: defaultModelId("claude") });
  });

  it("swaps a hidden default provider for the first enabled one", () => {
    saveLastModelChoice("claude", "claude:opus-5");
    setProjectProviderHidden("/repo/a", "claude", true);
    expect(defaultSessionChoice("/repo/a")).toEqual({
      harness: "codex",
      model: defaultModelId("codex"),
    });
    expect(defaultSessionChoice("/repo/b")).toEqual({
      harness: "claude",
      model: "claude:opus-5",
    });
  });

  it("uses a project's own provider and model when set", () => {
    saveLastModelChoice("claude", "claude:opus-5");
    setProjectDefaultProvider("/repo/a", "codex", "codex:gpt-5.4");
    expect(defaultSessionChoice("/repo/a")).toEqual({
      harness: "codex",
      model: "codex:gpt-5.4",
    });
    expect(defaultSessionChoice("/repo/b")).toEqual({
      harness: "claude",
      model: "claude:opus-5",
    });
  });

  it("keeps a provider the project still allows", () => {
    setProjectProviderHidden("/repo/a", "codex", true);
    expect(firstEnabledHarness("/repo/a", "claude")).toBe("claude");
    expect(firstEnabledHarness("/repo/a", "codex")).toBe("claude");
  });

  it("keeps the six most recently used unique models", () => {
    const models = ["claude:opus-5", "claude:sonnet-5", "claude:haiku-4.5", "claude:opus-4.6", "claude:sonnet-4.6", "claude:opus-4.5", "claude:fable-5"];
    for (const model of models) saveRecentModelChoice("claude", model);
    saveRecentModelChoice("claude", models[1]);
    expect(loadRecentModelChoices()).toEqual([models[1], models[6], models[5], models[4], models[3], models[2]].map((model) => ({ harness: "claude", model })));
  });
});

describe("model picker tabs", () => {
  const available = (id: HarnessId) =>
    id === "claude" || id === "codex";

  it("starts with favorites then installed providers", () => {
    expect(modelPickerTabs(available)).toEqual([
      "favorites",
      "claude",
      "codex",
    ]);
  });

  it("wraps left and right across favorites and providers", () => {
    expect(stepModelPickerTab("favorites", 1, available)).toBe("claude");
    expect(stepModelPickerTab("claude", 1, available)).toBe("codex");
    expect(stepModelPickerTab("codex", 1, available)).toBe("favorites");
    expect(stepModelPickerTab("favorites", -1, available)).toBe("codex");
  });

  it("treats an unavailable current tab as the start of the list", () => {
    const onlyClaude = (id: HarnessId) => id === "claude";
    expect(stepModelPickerTab("codex", 1, onlyClaude)).toBe("claude");
  });

  it("falls back to favorites when the current tab is hidden", () => {
    const onlyClaude = (id: HarnessId) => id === "claude";
    expect(coerceModelPickerTab("codex", onlyClaude)).toBe("favorites");
    expect(coerceModelPickerTab("claude", onlyClaude)).toBe("claude");
    expect(coerceModelPickerTab("favorites", available)).toBe("favorites");
  });
});

describe("picker provider visibility", () => {
  beforeEach(mockLocalStorage);
  afterEach(mockLocalStorage);

  it("shows every provider until the user hides one", () => {
    expect(loadHiddenPickerProviders()).toEqual([]);
    expect(isPickerProviderVisible("codex")).toBe(true);
    savePickerProviderVisible("codex", false);
    expect(isPickerProviderVisible("codex")).toBe(false);
    expect(isPickerProviderVisible("claude")).toBe(true);
    expect(loadHiddenPickerProviders()).toEqual(["codex"]);
    savePickerProviderVisible("codex", true);
    expect(isPickerProviderVisible("codex")).toBe(true);
    expect(loadHiddenPickerProviders()).toEqual([]);
  });

  it("omits hidden providers even before an install probe", () => {
    savePickerProviderVisible("codex", false);
    expect(showProviderInModelPicker("codex", true, false)).toBe(false);
    expect(showProviderInModelPicker("claude", true, false)).toBe(true);
  });

  it("omits uninstalled providers after the probe, keeps them before", () => {
    expect(showProviderInModelPicker("codex", false, false)).toBe(true);
    expect(showProviderInModelPicker("codex", false, true)).toBe(false);
    expect(showProviderInModelPicker("codex", true, true)).toBe(true);
  });
});

describe("live catalog overlays", () => {
  afterEach(() => {
    resetHarnessModelOverlays();
  });

  it("retains a saved Codex model and settings before its catalog loads", () => {
    resetHarnessModelOverlays();
    const model = resolveModel("codex", "codex:gpt-5.6-sol");
    expect(model).toMatchObject({
      id: "codex:gpt-5.6-sol",
      harness: "codex",
      name: "GPT-5.6-Sol",
      nativeId: "gpt-5.6-sol",
    });
    expect(
      mergeModelSettings(model, {
        reasoningEffort: "high",
        serviceTier: "priority",
      }),
    ).toEqual({ reasoningEffort: "high", serviceTier: "priority" });
    expect(resolveModel("codex")).toMatchObject({
      id: "",
      harness: "codex",
      name: "Codex",
    });
  });

  it("is empty until a CLI catalog replaces the fallback list", () => {
    expect(hasLiveCatalog("codex")).toBe(false);
    setHarnessModels("codex", [
      {
        id: "codex:gpt-5.4",
        harness: "codex",
        name: "GPT 5.4",
        nativeId: "gpt-5.4",
      },
    ]);
    expect(hasLiveCatalog("codex")).toBe(true);
    expect(hasLiveCatalog("claude")).toBe(false);
  });

  it("takes the default model a live catalog reports", () => {
    setHarnessModels(
      "grok",
      [
        {
          id: "grok:grok-4.6",
          harness: "grok",
          name: "Grok 4.6",
          nativeId: "grok-4.6",
        },
        {
          id: "grok:magpie/sub2api/deepseek-flash",
          harness: "grok",
          name: "deepseek-flash[1M] · Sub2API",
          nativeId: "magpie/sub2api/deepseek-flash",
        },
      ],
      { defaultId: "magpie/sub2api/deepseek-flash" },
    );

    expect(defaultModelId("grok")).toBe(
      "grok:magpie/sub2api/deepseek-flash",
    );
    expect(resolveModel("grok").id).toBe("grok:magpie/sub2api/deepseek-flash");
    expect(nativeModelId(defaultModelId("grok"))).toBe(
      "magpie/sub2api/deepseek-flash",
    );
  });

  it("keeps the bundled default when a live catalog reports none", () => {
    setHarnessModels("grok", [
      {
        id: "grok:grok-4.6",
        harness: "grok",
        name: "Grok 4.6",
        nativeId: "grok-4.6",
      },
    ]);

    expect(defaultModelId("grok")).toBe("grok:grok-4.6");
  });

  it("keeps saved Claude versions distinct from a live alias", () => {
    const live = [
      {
        id: "claude:sonnet",
        harness: "claude" as const,
        name: "Sonnet 5",
        nativeId: "sonnet",
      },
      {
        id: "claude:opus",
        harness: "claude" as const,
        name: "Opus 5",
        nativeId: "opus",
      },
    ];

    setHarnessModels("claude", live);
    expect(newSession("claude", "/repo", "claude:opus-5").model).toBe(
      "claude:opus-5",
    );
    const saved = resolveModel("claude", "claude:opus-5-5");
    expect(saved.id).toBe("claude:opus-5-5");
    expect(nativeModelId(saved)).toBe("claude-opus-5-5");

    // A relaunch starts with the built-in catalog until discovery completes.
    resetHarnessModelOverlays();
    const alias = resolveModel("claude", "claude:opus");
    expect(alias.id).toBe("claude:opus");
    expect(nativeModelId(alias)).toBe("opus");
    expect(newSession("claude", "/repo", "claude:opus").model).toBe(
      "claude:opus",
    );
  });

  it("keeps Opus 5.5 when the live catalog drops it", () => {
    // The CLI no longer advertises claude-opus-5-5, so every lookup for the
    // saved id misses. `opus-5-5` prefix-matches both `opus` and `opus-5`;
    // it must not settle for the alias, which silently ran Opus 5.
    setHarnessModels("claude", [
      {
        id: "claude:opus",
        harness: "claude" as const,
        name: "Opus",
        nativeId: "opus",
      },
      {
        id: "claude:opus-5",
        harness: "claude" as const,
        name: "Opus 5",
        nativeId: "claude-opus-5",
      },
      {
        id: "claude:sonnet",
        harness: "claude" as const,
        name: "Sonnet",
        nativeId: "sonnet",
      },
    ]);

    expect(resolveModel("claude", "claude:opus-5-5").id).toBe(
      "claude:opus-5-5",
    );
    expect(nativeModelId("claude:opus-5-5")).toBe("claude-opus-5-5");
    expect(encodeModelLaunchId("claude:opus-5-5")).toBe("claude-opus-5-5");
  });

  it("prefers the bundled versioned model over a singleton fuzzy match", () => {
    // Live catalog has only Opus 5, so `opus-5-5` prefix-matches that one
    // row. Returning it would give ModelSettings the wrong AgentModel for a
    // session saved on 5.5.
    setHarnessModels("claude", [
      {
        id: "claude:opus-5",
        harness: "claude" as const,
        name: "Opus 5",
        nativeId: "claude-opus-5",
      },
    ]);
    expect(resolveModel("claude", "claude:opus-5-5").id).toBe(
      "claude:opus-5-5",
    );
  });

  it("keeps a saved Claude version missing from both catalogs", () => {
    setHarnessModels("claude", [
      {
        id: "claude:sonnet",
        harness: "claude",
        name: "Sonnet",
        nativeId: "sonnet",
      },
      {
        id: "claude:opus-5",
        harness: "claude",
        name: "Opus 5",
        nativeId: "claude-opus-5",
      },
    ]);

    const model = resolveModel("claude", "claude:opus-5-6");
    expect(model).toMatchObject({
      id: "claude:opus-5-6",
      harness: "claude",
      nativeId: "claude-opus-5-6",
    });
    expect(newSession("claude", "/repo", "claude:opus-5-6").model).toBe(
      "claude:opus-5-6",
    );
    expect(nativeModelId(model)).toBe("claude-opus-5-6");

    const dotted = resolveModel("claude", "claude:opus-4.8");
    expect(dotted).toMatchObject({
      id: "claude:opus-4.8",
      nativeId: "claude-opus-4-8",
    });
    expect(nativeModelId("claude:opus-4.8")).toBe("claude-opus-4-8");
  });

  it("prefixes a short live-catalog native id before launching", () => {
    setHarnessModels("claude", [
      {
        id: "claude:opus-5-5",
        harness: "claude" as const,
        name: "Opus 5.5",
        nativeId: "opus-5-5",
      },
    ]);
    expect(nativeModelId("claude:opus-5-5")).toBe("claude-opus-5-5");
    expect(
      nativeModelId({
        id: "claude:opus-5-5",
        harness: "claude",
        name: "Opus 5.5",
        nativeId: "opus-5-5",
      }),
    ).toBe("claude-opus-5-5");
  });

  it.each([
    "sub2api/deepseek-flash",
    "deepseek-v3.2",
    "omarchy-vm/claude/claude-sonnet-4-6",
    "codex/gpt-5.6-sol",
    "custom-model-2",
    "opus",
    "claude-opus-5-5",
  ])("preserves the external Claude model id %s across launch paths", (native) => {
    const model: AgentModel = {
      id: `claude:${native}`,
      harness: "claude",
      name: native,
      nativeId: native,
    };
    // Saved keys must also work before a live catalog has been loaded.
    expect(nativeModelId(model.id)).toBe(native);
    expect(nativeModelId(model)).toBe(native);
    setHarnessModels("claude", [model]);
    expect(nativeModelId(model.id)).toBe(native);
  });

  it("rebuilds a Claude native id for a key no list knows", () => {
    expect(nativeModelId("claude:opus-4-8")).toBe("claude-opus-4-8");
    expect(nativeModelId("claude:opus-4-7")).toBe("claude-opus-4-7");
    expect(nativeModelId("claude:haiku-4-5")).toBe("claude-haiku-4-5");
    expect(nativeModelId("claude:opus-6")).toBe("claude-opus-6");
  });

  it("leaves a bare Claude alias and other providers alone", () => {
    expect(nativeModelId("claude:opus")).toBe("opus");
    expect(nativeModelId("claude:sonnet")).toBe("sonnet");
    expect(nativeModelId("codex:gpt-5.6-unreleased")).toBe(
      "gpt-5.6-unreleased",
    );
  });

  it("keeps a lone fuzzy match for a versioned id", () => {
    setHarnessModels("claude", [
      {
        id: "claude:opus-4-6",
        harness: "claude" as const,
        name: "Opus 4.6",
        nativeId: "claude-opus-4-6",
      },
    ]);
    expect(resolveModel("claude", "claude-opus-4-6").nativeId).toBe(
      "claude-opus-4-6",
    );
  });

  it("keeps a live Opus 5.5 id on Opus 5.5 across relaunch", () => {
    setHarnessModels("claude", [
      {
        id: "claude:opus-5-5",
        harness: "claude" as const,
        name: "Claude Opus 5.5",
        nativeId: "claude-opus-5-5",
      },
    ]);
    expect(resolveModel("claude", "claude:opus-5-5").nativeId).toBe(
      "claude-opus-5-5",
    );

    resetHarnessModelOverlays();
    expect(resolveModel("claude", "claude:opus-5-5").id).toBe(
      "claude:opus-5-5",
    );
    expect(resolveModel("claude", "claude:opus-5").id).toBe("claude:opus-5");
    expect(resolveModel("claude", "claude:opus").id).toBe("claude:opus");
  });

  it("keeps a saved alias when live discovery lists only versions", () => {
    setHarnessModels("claude", [
      {
        id: "claude:opus-5-20260101",
        harness: "claude" as const,
        name: "Opus 5",
        nativeId: "claude-opus-5-20260101",
      },
      {
        id: "claude:opus-5-5",
        harness: "claude" as const,
        name: "Opus 5.5",
        nativeId: "claude-opus-5-5",
      },
    ]);
    const alias = resolveModel("claude", "claude:opus");
    expect(alias.id).toBe("claude:opus");
    expect(nativeModelId(alias)).toBe("opus");
  });
});

/**
 * A bundled entry may omit `nativeId`, which means "the key minus the harness
 * prefix is the native id" (`codex:gpt-5.4` → `gpt-5.4`). An explicit `""` means
 * "omit --model and let the CLI choose", which is a real value.
 */
function expectedNative(id: string, nativeId?: string): string {
  if (nativeId !== undefined) return nativeId;
  const colon = id.indexOf(":");
  return colon >= 0 ? id.slice(colon + 1) : id;
}

function bundledByHarness(): Map<string, AgentModel[]> {
  const grouped = new Map<string, AgentModel[]>();
  for (const model of MODELS) {
    const list = grouped.get(model.harness) ?? [];
    list.push(model);
    grouped.set(model.harness, list);
  }
  return grouped;
}

describe("every bundled model resolves to its own native id", () => {
  beforeEach(() => resetHarnessModelOverlays());

  it("with no live catalog (first turn after launch)", () => {
    const wrong: string[] = [];
    for (const [harness, models] of bundledByHarness()) {
      for (const model of models) {
        const got = nativeModelId(model.id);
        const want = expectedNative(model.id, model.nativeId);
        if (got !== want) {
          wrong.push(`${harness}  ${model.id}  want ${want}  got ${got}`);
        }
      }
    }
    expect(wrong).toEqual([]);
  });

  it("with a live catalog that dropped the model (stale overlay)", () => {
    const wrong: string[] = [];
    for (const [harness, models] of bundledByHarness()) {
      setHarnessModels(harness as never, [models[0]]);
      for (const model of models) {
        const got = nativeModelId(model.id);
        const want = expectedNative(model.id, model.nativeId);
        if (got !== want) {
          wrong.push(`${harness}  ${model.id}  want ${want}  got ${got}`);
        }
      }
      resetHarnessModelOverlays();
    }
    expect(wrong).toEqual([]);
  });

  it("resolveModel never returns a model from another harness", () => {
    const wrong: string[] = [];
    for (const [harness, models] of bundledByHarness()) {
      setHarnessModels(harness as never, [models[0]]);
      for (const model of models) {
        const resolved = resolveModel(harness as never, model.id);
        if (resolved.harness !== harness) {
          wrong.push(
            `${harness}  ${model.id}  resolved to ${resolved.id} (${resolved.harness})`,
          );
        }
      }
      resetHarnessModelOverlays();
    }
    expect(wrong).toEqual([]);
  });

  it("encodeModelLaunchId never drops a provider prefix", () => {
    const wrong: string[] = [];
    for (const [harness, models] of bundledByHarness()) {
      setHarnessModels(harness as never, [models[0]]);
      for (const model of models) {
        const launch = encodeModelLaunchId(model.id, { effort: "high" });
        const base = launch.split("[")[0];
        const want = expectedNative(model.id, model.nativeId);
        if (base !== want) {
          wrong.push(`${harness}  ${model.id}  want ${want}  got ${base}`);
        }
      }
      resetHarnessModelOverlays();
    }
    expect(wrong).toEqual([]);
  });
});
