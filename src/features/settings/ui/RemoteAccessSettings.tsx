import { useCallback, useEffect, useState, type ReactNode } from "react";
import { t, useLocale, getLocale } from "../../../shared/i18n/locale";
import { transport } from "../../../platform/transport";
import { ask } from "../../../platform/dialog";
import { copyText } from "../../../platform/tauri/clipboard";
import { SecondaryButton } from "../../../shared/ui/SecondaryButton";
import { ChevronDown } from "../../../shared/ui/icons";

/** What `remote_settings_get` and `remote_settings_set` return. */
type RemoteSettings = {
  enabled: boolean;
  /** The user's own services; `null` uses the built-in ones, if any. */
  relay: string | null;
  registrationKey: string | null;
  registry: string | null;
  registryKey: string | null;
  name: string | null;
  autoConnect?: boolean | null;
  /** Which services this build carries; never their addresses or keys. */
  builtIn?: { relay: boolean; registry: boolean };
  /** The name used while `name` is unset: the computer's own. */
  defaultName?: string;
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

/** The code this computer shows, from `remote_pairing_start` and `remote_pairing_status`. */
type Pairing = { code: string; expiresAt: number };

/** How a pairing ended, from `remote-pairing-changed`. */
type PairingOutcome =
  | { state: "paired"; deviceId: string; name: string | null }
  | { state: "expired" }
  | { state: "failed"; error: string };

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

function asPairing(value: unknown): Pairing | null {
  return value != null && typeof value === "object" ? (value as Pairing) : null;
}

function lastActive(lastSeen: number | null): string {
  if (lastSeen == null) return t("No activity yet");
  const when = new Intl.DateTimeFormat(getLocale(), {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(lastSeen));
  return t("Last active {0}", when);
}

/** `9:05` for what is left until `expiresAt`. */
function remaining(expiresAt: number, now: number): string {
  const seconds = Math.max(0, Math.ceil((expiresAt - now) / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

/** Subscribes to `event` for the life of the component. */
function useRemoteEvent<T>(event: string, handler: (payload: T) => void): void {
  useEffect(() => {
    let stop: (() => void) | undefined;
    let live = true;
    void transport
      .listen<T>(event, ({ payload }) => handler(payload))
      .then((unlisten) => {
        if (live) stop = unlisten;
        else unlisten();
      })
      .catch(() => {
        // The page still works; only the broadcast is missing.
      });
    return () => {
      live = false;
      stop?.();
    };
  }, [event, handler]);
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

  const [pairing, setPairing] = useState<Pairing | null>(null);
  const [pairingBusy, setPairingBusy] = useState(false);
  const [pairingNote, setPairingNote] = useState<string | null>(null);
  const [pairingError, setPairingError] = useState<string | null>(null);
  const [now, setNow] = useState(() => Date.now());

  const [pairingCode, setPairingCode] = useState("");
  const [redeeming, setRedeeming] = useState(false);
  const [redeemNote, setRedeemNote] = useState<string | null>(null);
  const [redeemError, setRedeemError] = useState<string | null>(null);

  const [advancedOpen, setAdvancedOpen] = useState<boolean | null>(null);
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
    void loadGroup();
    void transport
      .call("remote_pairing_status")
      .then((value) => setPairing(asPairing(value)))
      .catch(() => {
        // No code on show is the same as none.
      });
  }, [loadSettings, loadGroup]);

  useRemoteEvent<{ enabled: boolean }>(
    "remote-status-changed",
    useCallback((payload) => {
      setSettings((current) => (current ? { ...current, enabled: payload.enabled } : current));
    }, []),
  );

  useRemoteEvent<PairingOutcome>(
    "remote-pairing-changed",
    useCallback(
      (outcome) => {
        setPairing(null);
        if (outcome.state === "paired") {
          setPairingError(null);
          setPairingNote(
            outcome.name
              ? t("{0} was added. It is connecting now.", outcome.name)
              : t("The device was added. It is connecting now."),
          );
          void loadGroup();
        } else if (outcome.state === "expired") {
          setPairingNote(null);
          setPairingError(t("The code expired. Add the device again for a new one."));
        } else {
          setPairingNote(null);
          setPairingError(t("Pairing failed: {0}", outcome.error));
        }
      },
      [loadGroup],
    ),
  );

  // The countdown under the code.
  useEffect(() => {
    if (pairing == null) return;
    setNow(Date.now());
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [pairing]);

  const savedRelay = settings?.relay ?? "";
  const savedRegistrationKey = settings?.registrationKey ?? "";
  const savedRegistry = settings?.registry ?? "";
  const savedRegistryKey = settings?.registryKey ?? "";
  const savedName = settings?.name ?? "";
  const builtIn = settings?.builtIn ?? { relay: false, registry: false };
  const servicesBuiltIn = builtIn.relay && builtIn.registry;

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
  // Without built-in services there is nothing to pair through until the
  // user names theirs, so Advanced starts open.
  const advancedShown = advancedOpen ?? (settings != null && !servicesBuiltIn);
  const addressesDirty =
    settings != null &&
    (relay.trim() !== savedRelay ||
      registrationKey.trim() !== savedRegistrationKey ||
      registry.trim() !== savedRegistry ||
      registryKey.trim() !== savedRegistryKey ||
      name.trim() !== savedName);

  async function changeSettings(
    patch: Partial<RemoteSettings>,
    failure: (reason: string) => string,
  ): Promise<void> {
    setSettingsError(null);
    try {
      const updated = asSettings(await transport.call("remote_settings_set", { settings: patch }));
      if (updated != null) setSettings(updated);
    } catch (reason) {
      setSettingsError(failure(reasonOf(reason)));
    }
  }

  async function setEnabled(next: boolean) {
    if (settings == null || toggling) return;
    setToggling(true);
    await changeSettings({ enabled: next }, (reason) =>
      t("Could not change remote access: {0}", reason),
    );
    setToggling(false);
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
    await changeSettings(patch, (reason) => t("Could not save remote settings: {0}", reason));
    // A new registry is where the group is read from, so read it again.
    void loadGroup();
    setSavingAddresses(false);
  }

  async function startPairing() {
    if (pairingBusy) return;
    setPairingBusy(true);
    setPairingNote(null);
    setPairingError(null);
    try {
      setPairing(asPairing(await transport.call("remote_pairing_start")));
      // It may have made the group and turned remote access on.
      void loadGroup();
      void loadSettings();
    } catch (reason) {
      setPairingError(t("Could not add a device: {0}", reasonOf(reason)));
    } finally {
      setPairingBusy(false);
    }
  }

  async function cancelPairing() {
    setPairing(null);
    try {
      await transport.call("remote_pairing_cancel");
    } catch (reason) {
      setPairingError(t("Could not cancel the code: {0}", reasonOf(reason)));
    }
  }

  async function redeem() {
    const code = pairingCode.trim();
    if (!code || redeeming) return;
    setRedeeming(true);
    setRedeemNote(null);
    setRedeemError(null);
    try {
      const host = (await transport.call<{ deviceId: string; name: string }>(
        "remote_pairing_redeem",
        { code },
      )) ?? { name: "" };
      setPairingCode("");
      setRedeemNote(t("Connected to {0}. Its window is open.", host.name));
      void loadGroup();
      void loadSettings();
    } catch (reason) {
      setRedeemError(t("Could not connect: {0}", reasonOf(reason)));
    } finally {
      setRedeeming(false);
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
      setPairing(null);
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
        description={t("Open this computer's workspace from your other computers.")}
      >
        <Row
          label={t("Allow other devices to connect to this computer")}
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
        id="remote-pairing"
        title={t("Add a device")}
        description={t("Show a code here, then type it on the other computer under Connect to another computer.")}
      >
        {pairing == null ? (
          <Row
            label={t("Add device")}
            description={t("The code works once and expires after 10 minutes. Adding a device turns remote access on.")}
          >
            <SecondaryButton disabled={pairingBusy} onClick={() => void startPairing()}>
              {pairingBusy ? t("Preparing…") : t("Add device")}
            </SecondaryButton>
          </Row>
        ) : (
          <Row
            label={
              <span
                aria-label={t("Pairing code")}
                className="font-mono text-[22px] font-semibold tracking-[0.12em] text-content"
              >
                {pairing.code}
              </span>
            }
            status={t("Type this code on the other computer. It expires in {0}.", remaining(pairing.expiresAt, now))}
          >
            <SecondaryButton onClick={() => void cancelPairing()}>{t("Cancel")}</SecondaryButton>
          </Row>
        )}
        {pairingNote ? <NoteLine>{pairingNote}</NoteLine> : null}
        {pairingError ? <ErrorLine>{pairingError}</ErrorLine> : null}
      </Group>

      <Group
        id="remote-connect"
        title={t("Connect to another computer")}
        description={t("Open the workspace of a computer that shows a code under Add a device.")}
      >
        <BlockRow
          label={t("Pairing code")}
          description={t("Type the code shown on the other computer. This computer joins its device group and opens it in a new window.")}
        >
          <div className="flex flex-wrap items-center gap-2">
            <input
              aria-label={t("Pairing code")}
              value={pairingCode}
              placeholder="K7QM-2XPA"
              spellCheck={false}
              autoComplete="off"
              autoCapitalize="characters"
              onChange={(event) => setPairingCode(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter") {
                  event.preventDefault();
                  void redeem();
                }
              }}
              className="h-8 w-40 min-w-0 rounded-md border border-content/10 bg-content/[0.04] px-2 font-mono text-[13px] tracking-[0.08em] text-content uppercase outline-none placeholder:text-content/30 focus:border-accent-ring/45"
            />
            <SecondaryButton
              disabled={!pairingCode.trim() || redeeming}
              onClick={() => void redeem()}
            >
              {redeeming ? t("Connecting…") : t("Connect")}
            </SecondaryButton>
          </div>
        </BlockRow>
        <Row
          label={t("Open the last computer at startup")}
          description={t("When it is online; otherwise Loci opens as usual. Turned on when this computer first pairs.")}
        >
          <Toggle
            label={t("Open the last computer at startup")}
            on={settings?.autoConnect ?? false}
            disabled={settings == null}
            onChange={(on) =>
              void changeSettings({ autoConnect: on }, (reason) =>
                t("Could not save remote settings: {0}", reason),
              )
            }
          />
        </Row>
        {redeemNote ? <NoteLine>{redeemNote}</NoteLine> : null}
        {redeemError ? <ErrorLine>{redeemError}</ErrorLine> : null}
      </Group>

      <Group
        id="devices"
        title={t("Devices")}
        description={t("Computers in the device group. The list refreshes every 30 seconds.")}
      >
        {status == null ? (
          <LoadingLine>{t("Loading devices…")}</LoadingLine>
        ) : group == null ? (
          <LoadingLine>{t("Add a device, or connect to another computer, to see devices here.")}</LoadingLine>
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
              status={`${device.platform} · ${lastActive(device.lastSeen)}`}
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

      <Group
        id="remote-advanced"
        title={
          <button
            type="button"
            aria-expanded={advancedShown}
            onClick={() => setAdvancedOpen(!advancedShown)}
            className="flex items-center gap-1.5 rounded text-left outline-none focus-visible:outline-2 focus-visible:outline-accent-ring"
          >
            {t("Advanced")}
            <ChevronDown
              className={`size-3.5 text-content/45 transition-transform ${advancedShown ? "" : "-rotate-90"}`}
            />
          </button>
        }
        description={t("The device name, the group key, and your own relay and registry.")}
        action={
          advancedShown ? (
            <SecondaryButton
              disabled={!addressesDirty || savingAddresses}
              onClick={() => void saveAddresses()}
            >
              {savingAddresses ? t("Saving…") : t("Save")}
            </SecondaryButton>
          ) : null
        }
      >
        {!advancedShown ? null : (
          <>
            <AddressRow
              label={t("Device name")}
              description={t("The name other devices see for this computer.")}
              value={name}
              placeholder={settings?.defaultName ?? "Loci"}
              onChange={setName}
              onCommit={() => void saveAddresses()}
            />
            {status == null ? (
              <LoadingLine>{t("Loading the device group…")}</LoadingLine>
            ) : group == null ? (
              <>
                <BlockRow
                  label={t("Join with a group key")}
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
                <Row
                  label={t("Create a device group")}
                  description={t("Adding a device creates one too. Create it here to share its group key instead of a code.")}
                >
                  <SecondaryButton disabled={groupBusy} onClick={() => void createGroup()}>
                    {t("Create device group")}
                  </SecondaryButton>
                </Row>
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
            {servicesBuiltIn ? (
              <NoteLine>{t("Loci's own relay and registry are used unless you fill in your own below.")}</NoteLine>
            ) : (
              <NoteLine>{t("This build of Loci has no relay or registry built in. Fill in your own to pair and connect devices.")}</NoteLine>
            )}
            <AddressRow
              label={t("Relay address")}
              description={t("The tunnel server that carries connections to this computer.")}
              value={relay}
              placeholder={builtIn.relay ? t("Loci's relay") : "wss://relay.example"}
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
              placeholder={builtIn.registry ? t("Loci's registry") : "https://registry.example"}
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
          </>
        )}
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
          <h2 title={description} className="text-[13px] font-semibold text-content">{title}</h2>
        </div>
        {action ? <div className="shrink-0 pb-0.5">{action}</div> : null}
      </div>
      {children ? (
        <div className="overflow-hidden rounded-xl border border-content/10 bg-content/3">{children}</div>
      ) : null}
    </section>
  );
}

/** A setting: its name (what it does is the hover text) and its control; `status` is what must show now. */
function Row({
  label,
  description,
  status,
  children,
}: {
  label: ReactNode;
  description?: string;
  status?: ReactNode;
  children?: ReactNode;
}) {
  useLocale();
  return (
    <div className="settings-row flex min-h-12 items-center gap-6 border-b border-content/5 px-4 py-2.5 last:border-b-0">
      <div className="min-w-0 flex-1" title={description}>
        <div className="text-[13px] text-content">{label}</div>
        {status ? <p role="status" className="mt-0.5 text-[12px] leading-relaxed text-content/50">{status}</p> : null}
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
      <div title={description} className="text-[13px] text-content">{label}</div>
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

function NoteLine({ children }: { children: ReactNode }) {
  return (
    <p role="status" className="border-b border-content/5 px-4 py-2.5 text-[12px] leading-relaxed text-content/55 last:border-b-0">
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
