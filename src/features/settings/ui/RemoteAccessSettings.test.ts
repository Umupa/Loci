// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { RemoteAccessSettings } from "./RemoteAccessSettings";

const invoke = vi.fn();
const ask = vi.fn(async () => true);
const copy = vi.fn(async () => {});
const eventListeners = vi.hoisted(
  () => new Map<string, Array<(event: { event: string; payload: { enabled: boolean } }) => void>>(),
);

vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => invoke(...args),
  convertFileSrc: (path: string) => path,
}));
vi.mock("@tauri-apps/api/event", () => ({
  listen: async (
    event: string,
    handler: (event: { event: string; payload: { enabled: boolean } }) => void,
  ) => {
    const listeners = eventListeners.get(event) ?? [];
    listeners.push(handler);
    eventListeners.set(event, listeners);
    return () => {
      const remaining = eventListeners.get(event) ?? [];
      eventListeners.set(
        event,
        remaining.filter((entry) => entry !== handler),
      );
    };
  },
}));
vi.mock("@tauri-apps/plugin-dialog", () => ({ ask: (...args: unknown[]) => ask(...args) }));
vi.mock("../../../platform/tauri/clipboard", () => ({
  copyText: (text: string) => copy(text),
}));

type RemoteSettings = {
  enabled: boolean;
  relay: string | null;
  registrationKey: string | null;
  registry: string | null;
  registryKey: string | null;
  name: string | null;
};

type GroupStatus = {
  deviceId: string;
  name: string;
  registry: string | null;
  group: { groupId: string; invite: string } | null;
};

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

const INVITE =
  "loci-group:BQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE?registry=https%3A%2F%2Fregistry.example";

let container: HTMLDivElement;
let root: Root;
let settings: RemoteSettings;
let group: GroupStatus;
let devices: Device[];
let connectFails: boolean;

function stored(): void {
  const data = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => data.set(key, value),
    removeItem: (key: string) => data.delete(key),
  });
}

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  stored();
  eventListeners.clear();
  ask.mockReset().mockResolvedValue(true);
  copy.mockReset().mockResolvedValue(undefined);
  connectFails = false;
  settings = {
    enabled: false,
    relay: "wss://relay.example",
    registrationKey: null,
    registry: "https://registry.example",
    registryKey: null,
    name: "Laptop",
  };
  group = {
    deviceId: "self",
    name: "Laptop",
    registry: "https://registry.example",
    group: null,
  };
  devices = [
    {
      deviceId: "self",
      name: "Laptop",
      platform: "macOS",
      addedAt: 1,
      lastSeen: 1_760_000_000_000,
      online: true,
      isSelf: true,
      connectable: false,
    },
    {
      deviceId: "mini",
      name: "Mac mini",
      platform: "macOS",
      addedAt: 2,
      lastSeen: 1_760_000_100_000,
      online: true,
      isSelf: false,
      connectable: true,
    },
    {
      deviceId: "old",
      name: "Old laptop",
      platform: "Linux",
      addedAt: 3,
      lastSeen: null,
      online: false,
      isSelf: false,
      connectable: false,
    },
  ];
  invoke.mockReset().mockImplementation(async (command: string, args?: unknown) => {
    switch (command) {
      case "remote_settings_get":
        return settings;
      case "remote_settings_set": {
        const patch = (args as { settings: Partial<RemoteSettings> }).settings;
        settings = { ...settings, ...patch };
        return settings;
      }
      case "remote_group_status":
        return group;
      case "remote_group_create":
        group = { ...group, group: { groupId: "group", invite: INVITE } };
        return group;
      case "remote_group_join":
        group = { ...group, group: { groupId: "group", invite: INVITE } };
        return group;
      case "remote_group_leave":
        group = { ...group, group: null };
        return group;
      case "remote_devices_list":
        return devices;
      case "remote_device_remove": {
        const { deviceId } = args as { deviceId: string };
        devices = devices.filter((device) => device.deviceId !== deviceId);
        return devices;
      }
      case "open_new_window":
        if (connectFails) throw new Error("Remote windows are not available yet");
        return undefined;
      default:
        return undefined;
    }
  });
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

async function render(): Promise<void> {
  await act(async () => root.render(createElement(RemoteAccessSettings)));
  await act(async () => {
    await Promise.resolve();
    await Promise.resolve();
  });
}

function text(): string {
  return container.textContent ?? "";
}

function button(label: string): HTMLButtonElement {
  const found = Array.from(container.querySelectorAll<HTMLButtonElement>("button")).find(
    (node) => node.textContent === label,
  );
  if (!found) throw new Error(`No button ${label}`);
  return found;
}

function buttons(label: string): HTMLButtonElement[] {
  return Array.from(container.querySelectorAll<HTMLButtonElement>("button")).filter(
    (node) => node.textContent === label,
  );
}

function input(label: string): HTMLInputElement {
  const found = container.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`);
  if (!found) throw new Error(`No input ${label}`);
  return found;
}

function toggle(): HTMLButtonElement {
  return container.querySelector<HTMLButtonElement>('[role="switch"][aria-label="Remote access"]')!;
}

function buttonByLabel(label: string): HTMLButtonElement {
  const found = container.querySelector<HTMLButtonElement>(`button[aria-label="${label}"]`);
  if (!found) throw new Error(`No button ${label}`);
  return found;
}

async function type(target: HTMLInputElement, value: string): Promise<void> {
  await act(async () => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(target, value);
    target.dispatchEvent(new Event("input", { bubbles: true }));
  });
}

async function blur(target: HTMLInputElement): Promise<void> {
  await act(async () => {
    target.dispatchEvent(new FocusEvent("focusout", { bubbles: true }));
  });
}

it("offers to create or join a group when this device is not in one", async () => {
  await render();
  expect(text()).toContain("Create device group");
  expect(text()).toContain("Join a device group");
  expect(text()).toContain("Join a device group to see its devices.");
  expect(input("Group key")).not.toBeNull();
  expect(toggle().getAttribute("aria-checked")).toBe("false");
  expect(input("Relay address").value).toBe("wss://relay.example");
  expect(input("Relay registration key").value).toBe("");
  expect(input("Registry address").value).toBe("https://registry.example");
  expect(input("Registry key").value).toBe("");
  expect(input("Device name").value).toBe("Laptop");
});

it("turns remote access on and off through remote_settings_set", async () => {
  await render();
  await act(async () => toggle().click());
  expect(invoke).toHaveBeenCalledWith("remote_settings_set", { settings: { enabled: true } });
  expect(toggle().getAttribute("aria-checked")).toBe("true");
  expect(text()).toContain("stays awake while it is plugged in");
});

it("follows remote-status-changed from another window", async () => {
  await render();
  await act(async () => {
    for (const handler of eventListeners.get("remote-status-changed") ?? []) {
      handler({ event: "remote-status-changed", payload: { enabled: true } });
    }
  });
  expect(toggle().getAttribute("aria-checked")).toBe("true");
});

it("saves an address when its field loses focus", async () => {
  await render();
  await type(input("Relay address"), "wss://new.example");
  await blur(input("Relay address"));
  expect(invoke).toHaveBeenCalledWith("remote_settings_set", {
    settings: { relay: "wss://new.example" },
  });
});

it("clears an address with null instead of an empty string", async () => {
  await render();
  await type(input("Registry address"), "");
  await blur(input("Registry address"));
  expect(invoke).toHaveBeenCalledWith("remote_settings_set", {
    settings: { registry: null },
  });
});

it("hides both keys until they are shown", async () => {
  settings = { ...settings, registrationKey: "relay-secret", registryKey: "registry-secret" };
  await render();
  const registration = input("Relay registration key");
  const registry = input("Registry key");
  expect(registration.type).toBe("password");
  expect(registry.type).toBe("password");
  expect(registration.value).toBe("relay-secret");
  expect(registry.value).toBe("registry-secret");
  expect(text()).toContain("Only needed when the relay is set up with RELAY_REGISTRATION_KEY.");
  expect(text()).toContain("Only needed when the registry is set up with REGISTRY_KEY.");

  await act(async () => buttonByLabel("Show relay registration key").click());
  expect(registration.type).toBe("text");
  expect(registry.type).toBe("password");
  await act(async () => buttonByLabel("Hide relay registration key").click());
  expect(registration.type).toBe("password");

  await act(async () => buttonByLabel("Show registry key").click());
  expect(registry.type).toBe("text");
  await act(async () => buttonByLabel("Hide registry key").click());
  expect(registry.type).toBe("password");
});

it("saves each key when its field loses focus", async () => {
  await render();
  await type(input("Relay registration key"), "relay-secret");
  await blur(input("Relay registration key"));
  expect(invoke).toHaveBeenCalledWith("remote_settings_set", {
    settings: { registrationKey: "relay-secret" },
  });

  await type(input("Registry key"), "registry-secret");
  await blur(input("Registry key"));
  expect(invoke).toHaveBeenCalledWith("remote_settings_set", {
    settings: { registryKey: "registry-secret" },
  });
});

it("clears a key with null instead of an empty string", async () => {
  settings = { ...settings, registrationKey: "relay-secret" };
  await render();
  await type(input("Relay registration key"), "");
  await blur(input("Relay registration key"));
  expect(invoke).toHaveBeenCalledWith("remote_settings_set", {
    settings: { registrationKey: null },
  });
});

it("submits only the address fields that changed", async () => {
  await render();
  await type(input("Registry key"), "registry-secret");
  await type(input("Device name"), "Study laptop");
  await act(async () => button("Save").click());
  expect(invoke).toHaveBeenCalledWith("remote_settings_set", {
    settings: { registryKey: "registry-secret", name: "Study laptop" },
  });
});

it("saves the device name with the Save button", async () => {
  await render();
  await type(input("Device name"), "Study laptop");
  await act(async () => button("Save").click());
  expect(invoke).toHaveBeenCalledWith("remote_settings_set", {
    settings: { name: "Study laptop" },
  });
});

it("creates a device group and shows its key masked", async () => {
  await render();
  await act(async () => button("Create device group").click());
  expect(invoke).toHaveBeenCalledWith("remote_group_create");
  expect(invoke.mock.calls.some(([command]) => command === "remote_group_create")).toBe(true);
  expect(text()).toContain("Anyone with this key can join the group and control this computer.");
  expect(text()).not.toContain(INVITE);
  expect(button("Show")).not.toBeNull();
});

it("joins with a pasted group key", async () => {
  await render();
  await type(input("Group key"), ` ${INVITE} `);
  await act(async () => button("Join").click());
  expect(invoke).toHaveBeenCalledWith("remote_group_join", { invite: INVITE });
  expect(text()).not.toContain(INVITE);
  expect(button("Show")).not.toBeNull();
});

it("shows and copies the group key", async () => {
  group = { ...group, group: { groupId: "group", invite: INVITE } };
  await render();
  expect(text()).not.toContain(INVITE);
  await act(async () => buttonByLabel("Show group key").click());
  expect(text()).toContain(INVITE);
  await act(async () => button("Copy").click());
  expect(copy).toHaveBeenCalledWith(INVITE);
  expect(text()).toContain("Copied");
});

it("lists online, offline, local and connectable devices", async () => {
  group = { ...group, group: { groupId: "group", invite: INVITE } };
  await render();
  expect(text()).toContain("Laptop");
  expect(text()).toContain("Mac mini");
  expect(text()).toContain("Old laptop");
  expect(text()).toContain("Online");
  expect(text()).toContain("Offline");
  expect(text()).toContain("This device");
  expect(buttons("Connect")).toHaveLength(1);
  expect(buttons("Remove")).toHaveLength(2);
});

it("asks before removing a device and removes it by id", async () => {
  group = { ...group, group: { groupId: "group", invite: INVITE } };
  await render();
  await act(async () => buttons("Remove")[0]!.click());
  expect(ask).toHaveBeenCalledWith(
    expect.stringContaining("Permanently remove Mac mini from the device group?"),
    expect.objectContaining({ kind: "warning", okLabel: "Remove" }),
  );
  expect(invoke).toHaveBeenCalledWith("remote_device_remove", { deviceId: "mini" });
  expect(text()).not.toContain("Mac mini");
});

it("keeps a device when the confirmation is dismissed", async () => {
  group = { ...group, group: { groupId: "group", invite: INVITE } };
  ask.mockResolvedValueOnce(false);
  await render();
  await act(async () => buttons("Remove")[0]!.click());
  expect(ask).toHaveBeenCalled();
  expect(invoke.mock.calls.some(([command]) => command === "remote_device_remove")).toBe(false);
  expect(text()).toContain("Mac mini");
});

it("asks before leaving the group and says the removal is permanent", async () => {
  group = { ...group, group: { groupId: "group", invite: INVITE } };
  await render();
  await act(async () => button("Leave device group").click());
  expect(ask).toHaveBeenCalledWith(
    expect.stringContaining("permanently removed from the device group"),
    expect.objectContaining({ kind: "warning", okLabel: "Leave group" }),
  );
  expect(invoke).toHaveBeenCalledWith("remote_group_leave");
  expect(text()).toContain("Create device group");
});

it("does not leave the group when the confirmation is dismissed", async () => {
  group = { ...group, group: { groupId: "group", invite: INVITE } };
  ask.mockResolvedValueOnce(false);
  await render();
  await act(async () => button("Leave device group").click());
  expect(ask).toHaveBeenCalled();
  expect(invoke.mock.calls.some(([command]) => command === "remote_group_leave")).toBe(false);
});

it("opens a remote window for a connectable device", async () => {
  group = { ...group, group: { groupId: "group", invite: INVITE } };
  await render();
  await act(async () => button("Connect").click());
  expect(invoke).toHaveBeenCalledWith("open_new_window", { remote: "device:mini" });
});

it("shows the error when a remote window cannot be opened", async () => {
  group = { ...group, group: { groupId: "group", invite: INVITE } };
  connectFails = true;
  await render();
  await act(async () => button("Connect").click());
  expect(text()).toContain("Could not connect to Mac mini: Remote windows are not available yet");
});

it("refreshes the device list every 30 seconds", async () => {
  group = { ...group, group: { groupId: "group", invite: INVITE } };
  vi.useFakeTimers();
  await render();
  const calls = () => invoke.mock.calls.filter(([command]) => command === "remote_devices_list");
  expect(calls()).toEqual([["remote_devices_list", { refresh: true }]]);
  await act(async () => {
    vi.advanceTimersByTime(30_000);
  });
  await act(async () => {
    await Promise.resolve();
  });
  expect(calls()).toEqual([
    ["remote_devices_list", { refresh: true }],
    ["remote_devices_list"],
  ]);
});
