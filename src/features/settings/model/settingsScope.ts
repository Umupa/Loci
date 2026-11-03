import { createContext, useContext } from "react";

/**
 * Whose settings a window shows. In a window connected to another device,
 * some settings are that host's (its models, permissions, CLIs) and some are
 * this device's own (appearance, shortcuts, alerts, its own remote access).
 * `null` in a window showing this device, where every setting is its own.
 */
export type RemoteSettingsScope = {
  /** The host's name, as the window's connection bar shows it. */
  host: string;
  /** The host cannot be reached: its settings are shown as last read, and cannot change. */
  offline: boolean;
};

export const RemoteSettingsScopeContext = createContext<RemoteSettingsScope | null>(null);

export const useRemoteSettingsScope = () => useContext(RemoteSettingsScopeContext);
