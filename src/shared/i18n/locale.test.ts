// @vitest-environment happy-dom
import { act, createElement, memo, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  getLocale, initLocale, loadLanguagePreference, resolveLocale,
  setLanguagePreference, subscribeLocale, t, useLocale,
} from "./locale";
import catalog from "./zh-CN.json";
import { searchSettings, KEYBINDINGS, filterKeybindings } from "../../features/settings/model/settings";
import { RUNTIME_MODES, RUNTIME_MODE_LABEL, RUNTIME_MODE_HINT } from "../../features/sessions/model/session";
import { formatRelativeTime } from "../lib/relativeTime";
import { EmptySession } from "../../features/sessions/ui/EmptySession";

let root: Root;
let host: HTMLDivElement;
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  setLanguagePreference("en");
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});
afterEach(async () => {
  await act(async () => root.unmount());
  host.remove();
  setLanguagePreference("system");
  localStorage.removeItem("loci.language");
  vi.unstubAllGlobals();
});

describe("language preferences", () => {
  it("respects explicit choices and the system's ordered supported languages", () => {
    expect(resolveLocale("en", ["zh-CN"])).toBe("en");
    expect(resolveLocale("zh-CN", ["en-US"])).toBe("zh-CN");
    expect(resolveLocale("system", ["ja-JP", "zh-Hans", "en"])).toBe("zh-CN");
    expect(resolveLocale("system", ["en-GB", "zh-CN"])).toBe("en");
    expect(resolveLocale("system", ["zh-TW"])).toBe("zh-CN");
    expect(resolveLocale("system", ["fr-FR"])).toBe("en");
  });

  it("persists explicit language choices and rejects obsolete stored values", () => {
    setLanguagePreference("zh-CN");
    expect(loadLanguagePreference()).toBe("zh-CN");
    expect(document.documentElement.lang).toBe("zh-CN");
    localStorage.setItem("loci.language", "invalid");
    expect(loadLanguagePreference()).toBe("system");
  });

  it("reacts to language changes and resets from another window", () => {
    const changed = vi.fn();
    const unsubscribe = subscribeLocale(changed);
    localStorage.setItem("loci.language", "zh-CN");
    window.dispatchEvent(new StorageEvent("storage", { key: "loci.language" }));
    expect(getLocale()).toBe("zh-CN");
    expect(document.documentElement.lang).toBe("zh-CN");
    expect(changed).toHaveBeenCalledTimes(1);
    localStorage.removeItem("loci.language");
    window.dispatchEvent(new StorageEvent("storage", { key: null }));
    expect(getLocale()).toBe(resolveLocale("system", navigator.languages));
    unsubscribe();
  });

  it("updates memoized UI without replacing a draft or translating user content", async () => {
    const stop = initLocale();
    const Draft = memo(function Draft() {
      useLocale();
      const [value] = useState("Settings {0} 中文草稿");
      return createElement(EmptySession, { cwd: "/preview/Settings", composer:
        createElement("textarea", { defaultValue: value, "aria-label": "draft" }) });
    });
    await act(async () => root.render(createElement(Draft)));
    const input = host.querySelector("textarea")!;
    input.value = "尚未发送的内容 {1}";
    await act(async () => setLanguagePreference("zh-CN"));
    expect(host.textContent).toContain("想在“Settings”中做些什么？");
    expect(host.querySelector("textarea")).toBe(input);
    expect(input.value).toBe("尚未发送的内容 {1}");
    await act(async () => setLanguagePreference("en"));
    expect(host.textContent).toContain("What should we work on in Settings?");
    expect(input.value).toBe("尚未发送的内容 {1}");
    stop();
  });
});

describe("Chinese UI copy", () => {
  it("preserves interpolation values verbatim without recursively replacing placeholders", () => {
    setLanguagePreference("zh-CN");
    expect(t('Saved to "{0}"', "项目 {1} <tag>")).toBe("已保存至“项目 {1} <tag>”");
    expect(t("Unknown source {0}", "raw")).toBe("Unknown source raw");
  });

  it("keeps placeholder sets identical across the catalog", () => {
    const tokens = (value: string) => [...new Set(value.match(/\{\d+\}/g) ?? [])].sort();
    for (const [source, translation] of Object.entries(catalog)) {
      expect(tokens(translation), source).toEqual(tokens(source));
      expect(translation.trim(), source).not.toBe("");
    }
  });

  it("searches Chinese settings and shortcut labels while keeping shortcut IDs stable", () => {
    setLanguagePreference("zh-CN");
    expect(searchSettings("语言").some((result) => result.settingId === "language")).toBe(true);
    expect(searchSettings("背景").some((result) => result.settingId === "chat-background")).toBe(true);
    expect(filterKeybindings(KEYBINDINGS, "向右分栏")[0].command).toBe("Pane: Split Right");
    expect(KEYBINDINGS.find((row) => row.command === "App: Settings")).toBeDefined();
  });

  it("states permission boundaries precisely and keeps wire values unchanged", () => {
    setLanguagePreference("zh-CN");
    expect(RUNTIME_MODES).toEqual(["supervised", "auto-accept-edits", "auto", "full-access"]);
    expect(RUNTIME_MODE_LABEL.supervised).toBe("逐项确认");
    expect(RUNTIME_MODE_HINT["auto-accept-edits"]).toContain("其他操作仍需确认");
    expect(RUNTIME_MODE_HINT["full-access"]).toContain("非规划回合");
    setLanguagePreference("en");
    expect(RUNTIME_MODE_LABEL.supervised).toBe("Supervised");
  });

  it("uses the selected language for relative time", () => {
    const now = Date.UTC(2026, 9, 9);
    setLanguagePreference("zh-CN");
    expect(formatRelativeTime(new Date(now - 3_600_000).toISOString(), now)).toBe("1小时前");
    setLanguagePreference("en");
    expect(formatRelativeTime(new Date(now - 3_600_000).toISOString(), now)).toBe("1 hour ago");
  });
});
