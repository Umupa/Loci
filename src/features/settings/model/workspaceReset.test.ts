// @vitest-environment happy-dom
import { beforeEach, expect, it } from "vitest";
import { clearWorkspaceStorage, workspaceKeysToRemove } from "./workspaceReset";

// Kept independently from the implementation so dropping a setting is caught.
const settings = `accentColor themeHue themeSaturation themeDarkLightness themeId themeBoot themeWallpaperAuto colorScheme codeFont uiFont uiScale sidebarOpacity sidebarBlur bodyGlass chatBackgroundPath chatBackgroundOpacity chatBackgroundEmptyOpacity chatBackgroundScope chatBackgroundSessionOpacity newThreadBackgroundEffect settingsSection followUpBehavior composerEffortVisible modelControls tabAnimationsEnabled tabLimit collapsedProjectRailMode composerRunner notesEnabled agentsEnabled liveAgentsEnabled closeToTray claudeHooks keybindingOverrides language sounds soundsEnabledAt notifications transcriptLayout transcriptAnchor defaultModels favoriteModels hiddenPickerProviders lastModel lastModelSettings recentModels modelPickerTab providerAccounts.v1 providerAccountSelections.v1 providerBinaryPaths.v1 disabledSkillPaths builtinExcalidrawMcpEnabled diffPalette files.showHidden showExcludedFiles`.split(" ").map((key) => `loci.${key}`);
const workspace = [
  ...`recentProjects archivedProjects projectGroups projectGroupAssignments projectLocations projectRailOrder projectRailPinned projectRailOpen projectRailWidth sessionFolders sessionSidebarFilters sessionSidebarOpen sessionsShowArchived pinnedSessionsCollapsed reminderSessionsCollapsed closedTabs.v1 notificationProjects.v2 projectNotifications.v1 projectProviderSettings.v1`.split(" ").map((key) => `loci.${key}`),
  ...`project-chat-backgrounds project-notifications project-notifications:/repo tab-group:colors tab-group:labels tab-group:logos tab-group:custom-colors tab-group:mascots tab-group:key-version tab-groups:collapsed agent-roster agent-workspaces.v1 agent-rotations agent-template-edits agent-previews agent-habits-active`.split(" ").map((key) => `loci:${key}`),
];
beforeEach(() => localStorage.clear());
it("preserves every setting verbatim while removing all workspace keys", () => {
  for (const key of [...settings, ...workspace, "another-app", "loci.chatBackgroundFuture"]) localStorage.setItem(key, `  raw:${key}  `);
  clearWorkspaceStorage(localStorage);
  for (const key of [...settings, "another-app", "loci.chatBackgroundFuture"]) expect(localStorage.getItem(key), key).toBe(`  raw:${key}  `);
  for (const key of workspace) expect(localStorage.getItem(key), key).toBeNull();
});
it("removes unknown Loci keys by default, without mutating the input or touching other namespaces", () => {
  const keys = Object.freeze(["loci.futureDocument", "loci:new-agent", "loci", "lociOther", "external"]);
  expect(workspaceKeysToRemove(keys)).toEqual(["loci.futureDocument", "loci:new-agent"]);
  expect(keys).toHaveLength(5);
  expect(workspaceKeysToRemove([])).toEqual([]);
});
