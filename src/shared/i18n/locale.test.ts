// @vitest-environment happy-dom
import { act, createElement, memo, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  getLocale, loadLanguagePreference, resolveLocale,
  setLanguagePreference, subscribeLocale, t,
} from "./locale";
import { SettingsLanguage, useUiText } from "./SettingsLanguage";
import catalog from "./zh-CN.json";
import { searchSettings, KEYBINDINGS, filterKeybindings } from "../../features/settings/model/settings";
import { RUNTIME_MODES, RUNTIME_MODE_LABEL, RUNTIME_MODE_HINT } from "../../features/sessions/model/session";
import { formatRelativeTime } from "../lib/relativeTime";
import { EmptySession } from "../../features/sessions/ui/EmptySession";
import { Modal } from "../ui/Modal";

let root: Root;
let host: HTMLDivElement;
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  document.documentElement.lang = "en";
  setLanguagePreference("en");
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});
afterEach(async () => {
  await act(async () => root.unmount());
  host.remove();
  setLanguagePreference("system");
  localStorage.clear();
  vi.unstubAllGlobals();
});

describe("settings language preferences", () => {
  it("respects explicit choices and the system's ordered supported languages", () => {
    expect(resolveLocale("en", ["zh-CN"])).toBe("en");
    expect(resolveLocale("zh-CN", ["en-US"])).toBe("zh-CN");
    expect(resolveLocale("system", ["ja-JP", "zh-Hans", "en"])).toBe("zh-CN");
    expect(resolveLocale("system", ["en-GB", "zh-CN"])).toBe("en");
    expect(resolveLocale("system", ["zh-TW"])).toBe("zh-CN");
    expect(resolveLocale("system", ["fr-FR"])).toBe("en");
  });

  it("persists settings choices without changing the workspace document language", () => {
    setLanguagePreference("zh-CN");
    expect(loadLanguagePreference()).toBe("zh-CN");
    expect(document.documentElement.lang).toBe("en");
    localStorage.setItem("loci.language", "invalid");
    expect(loadLanguagePreference()).toBe("system");
  });

  it("reacts to preference changes and resets from another window", () => {
    const changed = vi.fn();
    const unsubscribe = subscribeLocale(changed);
    localStorage.setItem("loci.language", "zh-CN");
    window.dispatchEvent(new StorageEvent("storage", { key: "loci.language" }));
    expect(getLocale()).toBe("zh-CN");
    expect(document.documentElement.lang).toBe("en");
    expect(changed).toHaveBeenCalledTimes(1);
    localStorage.removeItem("loci.language");
    window.dispatchEvent(new StorageEvent("storage", { key: null }));
    expect(getLocale()).toBe(resolveLocale("system", navigator.languages));
    unsubscribe();
  });

  it("reads changes made while Settings was closed and had no subscribers", () => {
    localStorage.setItem("loci.language", "zh-CN");
    expect(getLocale()).toBe("zh-CN");
    expect(t("Settings")).toBe("设置");
  });

  it("limits shared-control translations to Settings while retaining the workspace draft", async () => {
    const Label = memo(function Label() {
      const { t } = useUiText();
      return createElement("label", null, t("Settings"));
    });
    const Draft = memo(function Draft() {
      const [value] = useState("Settings {0} 中文草稿");
      return createElement(EmptySession, { cwd: "/preview/Settings", composer:
        createElement("textarea", { defaultValue: value, "aria-label": "draft" }) });
    });
    await act(async () => root.render(createElement("div", null,
      createElement(SettingsLanguage, { children: createElement(Label) }),
      createElement(Label), createElement(Draft))));
    const input = host.querySelector("textarea")!;
    input.value = "尚未发送的内容 {1}";
    await act(async () => setLanguagePreference("zh-CN"));
    expect([...host.querySelectorAll("label")].map((node) => node.textContent)).toEqual(["设置", "Settings"]);
    expect(host.querySelector('[lang="zh-CN"]')).not.toBeNull();
    expect(host.textContent).toContain("What should we work on in Settings?");
    expect(host.querySelector("textarea")).toBe(input);
    expect(input.value).toBe("尚未发送的内容 {1}");
    await act(async () => setLanguagePreference("en"));
    expect([...host.querySelectorAll("label")].map((node) => node.textContent)).toEqual(["Settings", "Settings"]);
    expect(input.value).toBe("尚未发送的内容 {1}");
  });

  it("keeps settings dialogs localized through portals without translating workspace controls", async () => {
    const TranslatedButton = () => {
      const { t } = useUiText();
      return createElement("button", { type: "button", "aria-label": t("Rename") }, t("Rename"));
    };
    setLanguagePreference("zh-CN");
    await act(async () => root.render(createElement("div", null,
      createElement(TranslatedButton),
      createElement(SettingsLanguage, { children: createElement(Modal, {
        title: "Settings preview", onClose: () => {},
        children: createElement(TranslatedButton),
      }) }))));
    expect(host.querySelector('[aria-label="Rename"]')).not.toBeNull();
    const dialog = document.querySelector('[role="dialog"]')!;
    expect(host.contains(dialog)).toBe(false);
    expect(dialog.querySelector('[aria-label="重命名"]')).not.toBeNull();
    expect(dialog.closest('[lang]')?.getAttribute("lang")).toBe("zh-CN");
    await act(async () => setLanguagePreference("en"));
    expect(dialog.querySelector('[aria-label="Rename"]')).not.toBeNull();
    expect(host.querySelector('[aria-label="Rename"]')).not.toBeNull();
  });
});

describe("settings copy", () => {
  it("preserves interpolation values verbatim without recursively replacing placeholders", () => {
    setLanguagePreference("zh-CN");
    expect(t("Delete {0}", "项目 {1} <tag>")).toBe("删除 项目 {1} <tag>");
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

  it("keeps composer permission names, hints and wire values in English", () => {
    setLanguagePreference("zh-CN");
    expect(RUNTIME_MODES).toEqual(["supervised", "auto-accept-edits", "auto", "full-access"]);
    expect(RUNTIME_MODE_LABEL.supervised).toBe("Supervised");
    expect(RUNTIME_MODE_HINT["auto-accept-edits"]).toBe("Auto-approve edits, ask before other actions.");
    expect(RUNTIME_MODE_HINT["full-access"]).toContain("non-plan turns without prompts");
  });

  it("keeps workspace dates in English regardless of the settings preference", () => {
    const now = Date.UTC(2026, 9, 9);
    setLanguagePreference("zh-CN");
    expect(formatRelativeTime(new Date(now - 3_600_000).toISOString(), now)).toBe("1 hour ago");
  });
});
