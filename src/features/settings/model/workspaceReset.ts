import { invoke } from "@tauri-apps/api/core";

// Settings are an explicit allowlist; new workspace keys are reset by default.
const SETTINGS = new Set([
  "accentColor", "themeHue", "themeSaturation", "themeDarkLightness", "themeId",
  "themeBoot", "themeWallpaperAuto", "colorScheme", "codeFont", "uiFont", "uiScale",
  "sidebarOpacity", "sidebarBlur", "bodyGlass", "newThreadBackgroundEffect",
  "settingsSection", "followUpBehavior", "composerEffortVisible", "modelControls",
  "tabAnimationsEnabled", "tabLimit", "collapsedProjectRailMode", "composerRunner",
  "notesEnabled", "agentsEnabled", "liveAgentsEnabled", "closeToTray", "claudeHooks",
  "keybindingOverrides", "language", "sounds",
  "soundsEnabledAt", "notifications", "transcriptLayout", "transcriptAnchor",
  "defaultModels", "favoriteModels", "hiddenPickerProviders", "lastModel",
  "lastModelSettings", "recentModels", "modelPickerTab", "providerAccounts.v1",
  "providerAccountSelections.v1", "providerBinaryPaths.v1", "disabledSkillPaths",
  "builtinExcalidrawMcpEnabled", "diffPalette", "files.showHidden", "showExcludedFiles",
].map((key) => `loci.${key}`));

export function workspaceKeysToRemove(keys: readonly string[]): string[] {
  return keys.filter((key) => (key.startsWith("loci.") || key.startsWith("loci:"))
    && !SETTINGS.has(key) && !key.startsWith("loci.chatBackground"));
}

export function clearWorkspaceStorage(storage: Storage): void {
  const keys = Array.from({ length: storage.length }, (_, index) => storage.key(index))
    .filter((key): key is string => key !== null);
  for (const key of workspaceKeysToRemove(keys)) storage.removeItem(key);
}

export function resetWorkspace(): Promise<void> {
  return invoke("workspace_reset");
}
