import { useCallback, useEffect, useState, type ReactNode } from "react";
import { t, useLocale, getLocale } from "../../../shared/i18n/locale";
import { transport } from "../../../platform/transport";
import { ask } from "../../../platform/dialog";
import { copyText } from "../../../platform/tauri/clipboard";
import { SecondaryButton } from "../../../shared/ui/SecondaryButton";

/** What `remote_settings_get` and `remote_settings_set` return. */
type RemoteSettings = {
  enabled: boolean;
  relay: string | null;
  registrationKey: string | null;
  registry: string | null;
  registryKey: string | null;
  name: string | null;
};

/** What the group commands return. */
type GroupStatus = {
  deviceId: string;
  name: string;
  registry: string | null;
  group: { groupId: string; invite: string } | null;
};

/** One row of `remote_devices_list`. */
type Device = {
  deviceId: string;
  name: string;
  platform: string;
  addedAt: number;
  lastSeen: number | null;
  online: boolean;
  isSelf: boolean;
  connectable: boolean;
};

/** How often the device list asks for fresh state while Settings stays open. */
const DEVICES_REFRESH_MS = 30_000;

function reasonOf(reason: unknown): string {
  return reason instanceof Error ? reason.message : String(reason);
}

function asSettings(value: unknown): RemoteSettings | null {
  return value != null && typeof value === "object" ? (value as RemoteSettings) : null;
}

function asGroup(value: unknown): GroupStatus | null {
  return value != null && typeof value === "object" ? (value as GroupStatus) : null;
}

function lastActive(lastSeen: number | null): string {
  if (lastSeen == null) return t("No activity yet");
  const when = new Intl.DateTimeFormat(getLocale(), {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(lastSeen));
  return t("Last active {0}", when);
}

export function RemoteAccessSettings() {
  useLocale();
  const [settings, setSettings] = useState<RemoteSettings | null>(null);
  const [status, setStatus] = useState<GroupStatus | null>(null);
  const [devices, setDevices] = useState<Device[] | null>(null);
  const [settingsError, setSettingsError] = useState<string | null>(null);
  const [groupError, setGroupError] = useState<string | null>(null);
  const [devicesError, setDevicesError] = useState<string | null>(null);
  const [toggling, setToggling] = useState(false);
  const [savingAddresses, setSavingAddresses] = useState(false);
  const [groupBusy, setGroupBusy] = useState(false);
  const [deviceBusy, setDeviceBusy] = useState<string | null>(null);

  const [relay, setRelay] = useState("");
  const [registrationKey, setRegistrationKey] = useState("");
  const [registry, setRegistry] = useState("");
  const [registryKey, setRegistryKey] = useState("");
  const [name, setName] = useState("");

  const [invite, setInvite] = useState("");
  const [inviteVisible, setInviteVisible] = useState(false);
  const [copied, setCopied] = useState(false);

  const loadSettings = useCallback(async () => {
    try {
      const next = asSettings(await transport.call("remote_settings_get"));
      if (next == null) return;
      setSettings(next);
      setSettingsError(null);
    } catch (reason) {
      setSettingsError(t("Could not load remote settings: {0}", reasonOf(reason)));
    }
  }, []);

  const loadGroup = useCallback(async () => {
    try {
      const next = asGroup(await transport.call("remote_group_status"));
      if (next == null) return;
      setStatus(next);
      setGroupError(null);
    } catch (reason) {
      setGroupError(t("Could not load the device group: {0}", reasonOf(reason)));
    }
  }, []);

  useEffect(() => {
    void loadSettings();
    let stop: (() => void) | undefined;
    let live = true;
    void transport
      .listen<{ enabled: boolean }>("remote-status-changed", ({ payload }) => {
        setSettings((current) => (current ? { ...current, enabled: payload.enabled } : current));
      })
      .then((unlisten) => {
        if (live) stop = unlisten;
        else unlisten();
      })
      .catch(() => {
        // The switch still works; only the broadcast is missing.
      });
    return () => {
      live = false;
      stop?.();
    };
  }, [loadSettings]);

  useEffect(() => {
    void loadGroup();
  }, [loadGroup]);

  const savedRelay = settings?.relay ?? "";
  const savedRegistrationKey = settings?.registrationKey ?? "";
  const savedRegistry = settings?.registry ?? "";
  const savedRegistryKey = settings?.registryKey ?? "";
  const savedName = settings?.name ?? "";

  // Follow the saved values without discarding an address being typed.
  useEffect(() => setRelay(savedRelay), [savedRelay]);
  useEffect(() => setRegistrationKey(savedRegistrationKey), [savedRegistrationKey]);
  useEffect(() => setRegistry(savedRegistry), [savedRegistry]);
  useEffect(() => setRegistryKey(savedRegistryKey), [savedRegistryKey]);
  useEffect(() => setName(savedName), [savedName]);

  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), 1500);
    return () => window.clearTimeout(timer);
  }, [copied]);

  const groupId = status?.group?.groupId ?? null;

  // Only members have devices. Joining, leaving and a changed registry all
  // change the group id, which reloads the list.
  useEffect(() => {
    if (!groupId) {
      setDevices([]);
      setDevicesError(null);
      return;
    }
    let live = true;
    const load = async (refresh: boolean) => {
      try {
        const list = refresh
          ? await transport.call<Device[]>("remote_devices_list", { refresh: true })
          : await transport.call<Device[]>("remote_devices_list");
        if (!live) return;
        setDevices(Array.isArray(list) ? list : []);
        setDevicesError(null);
      } catch (reason) {
        if (live) setDevicesError(t("Could not load devices: {0}", reasonOf(reason)));
      }
    };
    setDevices(null);
    void load(true);
    const timer = window.setInterval(() => void load(false), DEVICES_REFRESH_MS);
    return () => {
      live = false;
      window.clearInterval(timer);
    };
  }, [groupId]);

  const enabled = settings?.enabled ?? false;
  const group = status?.group ?? null;
  const addressesDirty =
    settings != null &&
    (relay.trim() !== savedRelay ||
      registrationKey.trim() !== savedRegistrationKey ||
      registry.trim() !== savedRegistry ||
      registryKey.trim() !== savedRegistryKey ||
      name.trim() !== savedName);

  async function setEnabled(next: boolean) {
    if (settings == null || toggling) return;
    setToggling(true);
    setSettingsError(null);
    try {
      const updated = asSettings(
        await transport.call("remote_settings_set", { settings: { enabled: next } }),
      );
      if (updated != null) setSettings(updated);
    } catch (reason) {
      setSettingsError(t("Could not change remote access: {0}", reasonOf(reason)));
    } finally {
      setToggling(false);
    }
  }

  async function saveAddresses() {
    if (settings == null || !addressesDirty || savingAddresses) return;
    const patch: Record<string, string | null> = {};
    if (relay.trim() !== savedRelay) patch.relay = relay.trim() || null;
    if (registrationKey.trim() !== savedRegistrationKey)
      patch.registrationKey = registrationKey.trim() || null;
    if (registry.trim() !== savedRegistry) patch.registry = registry.trim() || null;
    if (registryKey.trim() !== savedRegistryKey) patch.registryKey = registryKey.trim() || null;
    if (name.trim() !== savedName) patch.name = name.trim() || null;
    if (Object.keys(patch).length === 0) return;
    setSavingAddresses(true);
    setSettingsError(null);
    try {
      const updated = asSettings(
        await transport.call("remote_settings_set", { settings: patch }),
      );
      if (updated != null) setSettings(updated);
      // A new registry is where the group is read from, so read it again.
      void loadGroup();
    } catch (reason) {
      setSettingsError(t("Could not save remote settings: {0}", reasonOf(reason)));
    } finally {
      setSavingAddresses(false);
    }
  }

  async function createGroup() {
    if (groupBusy) return;
    setGroupBusy(true);
    setGroupError(null);
    try {
      const next = asGroup(await transport.call("remote_group_create"));
      if (next != null) setStatus(next);
      void loadSettings();
    } catch (reason) {
      setGroupError(t("Could not create a device group: {0}", reasonOf(reason)));
    } finally {
      setGroupBusy(false);
    }
  }

  async function joinGroup() {
    const key = invite.trim();
    if (!key || groupBusy) return;
    setGroupBusy(true);
    setGroupError(null);
    try {
      const next = asGroup(await transport.call("remote_group_join", { invite: key }));
      if (next != null) setStatus(next);
      setInvite("");
      void loadSettings();
    } catch (reason) {
      setGroupError(t("Could not join the device group: {0}", reasonOf(reason)));
    } finally {
      setGroupBusy(false);
    }
  }

  async function leaveGroup() {
    if (groupBusy) return;
    const confirmed = await ask(
      t("This device is permanently removed from the device group. Its device key stops working at once, and to use the group again you must join as a new device with the group key."),
      {
        title: t("Leave device group?"),
        kind: "warning",
        okLabel: t("Leave group"),
        cancelLabel: t("Cancel"),
      },
    );
    if (!confirmed) return;
    setGroupBusy(true);
    setGroupError(null);
    try {
      const next = asGroup(await transport.call("remote_group_leave"));
      if (next != null) setStatus(next);
      setInviteVisible(false);
    } catch (reason) {
      setGroupError(t("Could not leave the device group: {0}", reasonOf(reason)));
    } finally {
      setGroupBusy(false);
    }
  }

  async function copyInvite(key: string) {
    setGroupError(null);
    try {
      await copyText(key);
      setCopied(true);
    } catch (reason) {
      setGroupError(t("Could not copy the group key: {0}", reasonOf(reason)));
    }
  }

  async function removeDevice(device: Device) {
    if (deviceBusy != null) return;
    const confirmed = await ask(
      t("Permanently remove {0} from the device group? Its device key stops working at once, and it must join again with the group key.", device.name),
      {
        title: t("Remove {0}?", device.name),
        kind: "warning",
        okLabel: t("Remove"),
        cancelLabel: t("Cancel"),
      },
    );
    if (!confirmed) return;
    setDeviceBusy(device.deviceId);
    setDevicesError(null);
    try {
      const list = await transport.call<Device[]>("remote_device_remove", {
        deviceId: device.deviceId,
      });
      setDevices(Array.isArray(list) ? list : []);
    } catch (reason) {
      setDevicesError(t("Could not remove {0}: {1}", device.name, reasonOf(reason)));
    } finally {
      setDeviceBusy(null);
    }
  }

  async function connectToDevice(device: Device) {
    if (deviceBusy != null) return;
    setDeviceBusy(device.deviceId);
    setDevicesError(null);
    try {
      await transport.call("open_new_window", { remote: `device:${device.deviceId}` });
    } catch (reason) {
      setDevicesError(t("Could not connect to {0}: {1}", device.name, reasonOf(reason)));
    } finally {
      setDeviceBusy(null);
    }
  }

  return (
    <>
      <Group
        id="remote-enabled"
        title={t("Remote access")}
        description={t("Serve this workspace to your other devices.")}
      >
        <Row
          label={t("Remote access")}
          description={
            enabled
              ? t("On. While remote access is on, this computer stays awake while it is plugged in.")
              : t("Off. Only this computer can open its workspace.")
          }
        >
          <Toggle
            label={t("Remote access")}
            on={enabled}
            disabled={settings == null || toggling}
            onChange={(on) => void setEnabled(on)}
          />
        </Row>
        {settingsError ? <ErrorLine>{settingsError}</ErrorLine> : null}
      </Group>

      <Group
        id="remote-addresses"
        title={t("Service addresses")}
        description={t("Where this computer registers and how other devices name it.")}
        action={
          <SecondaryButton
            disabled={!addressesDirty || savingAddresses}
            onClick={() => void saveAddresses()}
          >
            {savingAddresses ? t("Saving…") : t("Save")}
          </SecondaryButton>
        }
      >
        <AddressRow
          label={t("Relay address")}
          description={t("The tunnel server that carries connections to this computer.")}
          value={relay}
          placeholder="wss://relay.example"
          onChange={setRelay}
          onCommit={() => void saveAddresses()}
        />
        <AddressRow
          label={t("Relay registration key")}
          description={t("Only needed when the relay is set up with RELAY_REGISTRATION_KEY.")}
          value={registrationKey}
          placeholder={t("Not set")}
          secret={{ show: t("Show relay registration key"), hide: t("Hide relay registration key") }}
          onChange={setRegistrationKey}
          onCommit={() => void saveAddresses()}
        />
        <AddressRow
          label={t("Registry address")}
          description={t("Where the device group keeps its list of devices.")}
          value={registry}
          placeholder="https://registry.example"
          onChange={setRegistry}
          onCommit={() => void saveAddresses()}
        />
        <AddressRow
          label={t("Registry key")}
          description={t("Only needed when the registry is set up with REGISTRY_KEY.")}
          value={registryKey}
          placeholder={t("Not set")}
          secret={{ show: t("Show registry key"), hide: t("Hide registry key") }}
          onChange={setRegistryKey}
          onCommit={() => void saveAddresses()}
        />
        <AddressRow
          label={t("Device name")}
          description={t("The name other devices see for this computer.")}
          value={name}
          placeholder="Loci"
          onChange={setName}
          onCommit={() => void saveAddresses()}
        />
      </Group>

      <Group
        id="device-group"
        title={t("Device group")}
        description={t("Devices in one group trust each other and can reach this computer.")}
      >
        {status == null ? (
          <LoadingLine>{t("Loading the device group…")}</LoadingLine>
        ) : group == null ? (
          <>
            <BlockRow
              label={t("Create a device group")}
              description={t("Start a group here, then copy its group key to the other devices. This needs a registry address above.")}
            >
              <SecondaryButton disabled={groupBusy} onClick={() => void createGroup()}>
                {t("Create device group")}
              </SecondaryButton>
            </BlockRow>
            <BlockRow
              label={t("Join a device group")}
              description={t("Paste the group key from a device that is already in the group.")}
            >
              <div className="flex flex-wrap items-center gap-2">
                <input
                  aria-label={t("Group key")}
                  value={invite}
                  placeholder="loci-group:…?registry=…"
                  spellCheck={false}
                  autoComplete="off"
                  onChange={(event) => setInvite(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") {
                      event.preventDefault();
                      void joinGroup();
                    }
                  }}
                  className="h-8 min-w-0 flex-1 rounded-md border border-content/10 bg-content/[0.04] px-2 font-mono text-[11px] text-content outline-none placeholder:text-content/30 focus:border-accent-ring/45"
                />
                <SecondaryButton
                  disabled={!invite.trim() || groupBusy}
                  onClick={() => void joinGroup()}
                >
                  {t("Join")}
                </SecondaryButton>
              </div>
            </BlockRow>
          </>
        ) : (
          <>
            <BlockRow
              label={t("Group key")}
              description={t("Anyone with this key can join the group and control this computer.")}
            >
              <div className="flex flex-wrap items-center gap-2">
                <code className="min-w-0 flex-1 rounded-md bg-content/5 px-2 py-1.5 font-mono text-[11px] leading-relaxed break-all text-content/70">
                  {inviteVisible ? group.invite : "••••••••••••••••••••••••••••••••"}
                </code>
                <SecondaryButton
                  aria-label={inviteVisible ? t("Hide group key") : t("Show group key")}
                  onClick={() => setInviteVisible(!inviteVisible)}
                >
                  {inviteVisible ? t("Hide") : t("Show")}
                </SecondaryButton>
                <SecondaryButton
                  aria-label={t("Copy group key")}
                  onClick={() => void copyInvite(group.invite)}
                >
                  {copied ? t("Copied") : t("Copy")}
                </SecondaryButton>
              </div>
            </BlockRow>
            <Row
              label={t("Leave device group")}
              description={t("This device is removed permanently. To return, join again as a new device with the group key.")}
            >
              <SecondaryButton danger disabled={groupBusy} onClick={() => void leaveGroup()}>
                {t("Leave device group")}
              </SecondaryButton>
            </Row>
          </>
        )}
        {groupError ? <ErrorLine>{groupError}</ErrorLine> : null}
      </Group>

      <Group
        id="devices"
        title={t("Devices")}
        description={t("Computers in the device group. The list refreshes every 30 seconds.")}
      >
        {status == null ? (
          <LoadingLine>{t("Loading devices…")}</LoadingLine>
        ) : group == null ? (
          <LoadingLine>{t("Join a device group to see its devices.")}</LoadingLine>
        ) : devices == null ? (
          <LoadingLine>{t("Loading devices…")}</LoadingLine>
        ) : devices.length === 0 ? (
          <LoadingLine>{t("No devices in this group yet.")}</LoadingLine>
        ) : (
          devices.map((device) => (
            <Row
              key={device.deviceId}
              label={
                <span className="flex min-w-0 flex-wrap items-center gap-2">
                  <span className="truncate">{device.name}</span>
                  <span
                    className={`inline-flex items-center gap-1.5 text-[11px] ${device.online ? "text-content/60" : "text-content/35"}`}
                  >
                    <span
                      aria-hidden
                      className={`size-1.5 shrink-0 rounded-full ${device.online ? "bg-content/60" : "bg-content/20"}`}
                    />
                    {device.online ? t("Online") : t("Offline")}
                  </span>
                  {device.isSelf ? (
                    <span className="rounded bg-content/5 px-1.5 py-0.5 text-[10px] text-content/50">
                      {t("This device")}
                    </span>
                  ) : null}
                </span>
              }
              description={`${device.platform} · ${lastActive(device.lastSeen)}`}
            >
              {device.connectable ? (
                <SecondaryButton
                  disabled={deviceBusy != null}
                  onClick={() => void connectToDevice(device)}
                >
                  {t("Connect")}
                </SecondaryButton>
              ) : null}
              {device.isSelf ? null : (
                <SecondaryButton
                  danger
                  disabled={deviceBusy != null}
                  onClick={() => void removeDevice(device)}
                >
                  {t("Remove")}
                </SecondaryButton>
              )}
            </Row>
          ))
        )}
        {devicesError ? <ErrorLine>{devicesError}</ErrorLine> : null}
      </Group>
    </>
  );
}

function Group({
  id,
  title,
  description,
  action,
  children,
}: {
  /** Matches a `SETTINGS_INDEX` id when the whole card is the search target. */
  id?: string;
  title: ReactNode;
  description?: string;
  action?: ReactNode;
  children: ReactNode;
}) {
  useLocale();
  return (
    <section id={id ? `setting-${id}` : undefined} data-setting-id={id} className="pt-8 first:pt-0">
      <div className="flex items-end gap-4 pb-2.5">
        <div className="min-w-0 flex-1">
          <h2 className="text-[13px] font-semibold text-content">{title}</h2>
          {description ? (
            <p className="mt-1 text-[12px] leading-relaxed text-content/45">{description}</p>
          ) : null}
        </div>
        {action ? <div className="shrink-0 pb-0.5">{action}</div> : null}
      </div>
      <div className="overflow-hidden rounded-xl border border-content/10 bg-content/3">{children}</div>
    </section>
  );
}

function Row({
  label,
  description,
  children,
}: {
  label: ReactNode;
  description?: string;
  children?: ReactNode;
}) {
  useLocale();
  return (
    <div className="settings-row flex items-start gap-6 border-b border-content/5 px-4 py-3.5 last:border-b-0">
      <div className="min-w-0 flex-1">
        <div className="text-[13px] font-medium text-content">{label}</div>
        {description ? (
          <p className="mt-1 text-[12px] leading-relaxed text-content/45">{description}</p>
        ) : null}
      </div>
      <div className="settings-row-control flex min-w-0 max-w-[60%] shrink-0 flex-wrap items-center justify-end gap-2">
        {children}
      </div>
    </div>
  );
}

function BlockRow({
  label,
  description,
  children,
}: {
  label: ReactNode;
  description?: string;
  children: ReactNode;
}) {
  useLocale();
  return (
    <div className="border-b border-content/5 px-4 py-3.5 last:border-b-0">
      <div className="text-[13px] font-medium text-content">{label}</div>
      {description ? (
        <p className="mt-1 text-[12px] leading-relaxed text-content/45">{description}</p>
      ) : null}
      <div className="mt-3">{children}</div>
    </div>
  );
}

function AddressRow({
  label,
  description,
  value,
  placeholder,
  secret,
  onChange,
  onCommit,
}: {
  label: string;
  description: string;
  value: string;
  placeholder: string;
  /** A credential: hidden until shown, with a button beside the field. */
  secret?: { show: string; hide: string };
  onChange: (value: string) => void;
  onCommit: () => void;
}) {
  useLocale();
  const [visible, setVisible] = useState(false);
  return (
    <Row label={label} description={description}>
      <div className="flex min-w-0 items-center gap-2">
        <input
          aria-label={label}
          type={secret && !visible ? "password" : "text"}
          value={value}
          placeholder={placeholder}
          spellCheck={false}
          autoComplete="off"
          onChange={(event) => onChange(event.target.value)}
          onBlur={onCommit}
          className="h-8 w-64 min-w-0 max-w-full rounded-md border border-content/10 bg-content/[0.04] px-2 font-mono text-[11px] text-content outline-none placeholder:font-sans placeholder:text-content/30 focus:border-accent-ring/45"
        />
        {secret ? (
          <SecondaryButton
            aria-label={visible ? secret.hide : secret.show}
            onClick={() => setVisible(!visible)}
          >
            {visible ? t("Hide") : t("Show")}
          </SecondaryButton>
        ) : null}
      </div>
    </Row>
  );
}

function Toggle({
  label,
  on,
  onChange,
  disabled = false,
}: {
  label: string;
  on: boolean;
  onChange: (on: boolean) => void;
  disabled?: boolean;
}) {
  useLocale();
  return (
    <button
      type="button"
      role="switch"
      aria-label={label}
      aria-checked={on}
      disabled={disabled}
      onClick={() => onChange(!on)}
      className={`relative h-5 w-9 shrink-0 rounded-full transition-colors disabled:cursor-not-allowed disabled:opacity-40 ${on ? "bg-accent" : "bg-content/20"}`}
    >
      <span
        className={`absolute top-0.5 size-4 rounded-full bg-white transition-[left] ${on ? "left-4.5" : "left-0.5"}`}
      />
    </button>
  );
}

function ErrorLine({ children }: { children: ReactNode }) {
  return (
    <p
      role="alert"
      className="border-t border-content/5 px-4 py-2 text-[12px] leading-relaxed break-words text-red-400"
    >
      {children}
    </p>
  );
}

function LoadingLine({ children }: { children: ReactNode }) {
  return (
    <p role="status" className="px-4 py-3.5 text-[12px] text-content/45">
      {children}
    </p>
  );
}
