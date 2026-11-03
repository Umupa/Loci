/**
 * Settings that decide what the host does: its models, permissions, projects
 * and agent CLIs. A window connected to another device shows that device's
 * values, kept under the same keys in its own storage, and changes them there.
 * Every other setting (appearance, layout, what is open) stays per device.
 * The mentor roster is not here: it comes from the host's registry.
 */
export const HOST_SHARED_KEYS: readonly string[] = [
  "loci:agent-default-access",
  "loci.learningLanguage",
  "loci.defaultModels",
  "loci.lastModel",
  "loci.lastModelSettings",
  "loci.hiddenPickerProviders",
  "loci.projectProviderSettings.v1",
  "loci.providerAccounts.v1",
  "loci.providerAccountSelections.v1",
  "loci.providerBinaryPaths.v1",
  "loci.followUpBehavior",
  "loci.claudeHooks",
  "loci.disabledSkillPaths",
  "loci.recentProjects",
  "loci.archivedProjects",
];

/** A whole settings value at most; the largest are project lists. */
export const HOST_SETTING_MAX_CHARS = 64 * 1024;

export type HostSettingValues = Record<string, string | null>;

const shared = new Set(HOST_SHARED_KEYS);
let sink: ((key: string) => void) | undefined;
const refreshers = new Map<string, () => void>();

export const isHostSharedKey = (key: string) => shared.has(key);

/**
 * A module saved a host-shared setting. The host passes it on to connected
 * devices; a connected window sends it to the host. Nothing happens otherwise.
 */
export function hostSettingWritten(key: string): void {
  sink?.(key);
}

/** Who hears about saved settings: the host's feed, or a connected window's link to its host. */
export function setHostSettingSink(next: ((key: string) => void) | undefined): void {
  sink = next;
}

/** For a module that keeps no `storage` listener: how it learns a value changed under it. */
export function onHostSettingApplied(key: string, refresh: () => void): void {
  refreshers.set(key, refresh);
}

export function hostSettingsSnapshot(): HostSettingValues {
  return Object.fromEntries(HOST_SHARED_KEYS.map((key) => [key, localStorage.getItem(key)]));
}

/**
 * Stores values that came from the other side and tells this window's readers,
 * as a write from another window would (`storage`). Unknown keys are ignored.
 */
export function applyHostSettings(values: HostSettingValues): void {
  for (const [key, value] of Object.entries(values)) {
    if (!shared.has(key)) continue;
    const oldValue = localStorage.getItem(key);
    if (oldValue === value) continue;
    if (value === null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
    window.dispatchEvent(new StorageEvent("storage", { key, oldValue, newValue: value, storageArea: localStorage }));
    refreshers.get(key)?.();
  }
}
