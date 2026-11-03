import React from "react";
import ReactDOM from "react-dom/client";
import { BootGate } from "./bootSplash";
import { REMOTE_TARGET, transport } from "./platform/transport";
import { applyHostSettings, setHostSettingSink } from "./platform/hostSettings";
import { applyHostModels } from "./app/remote/hostModels";
import { pickOnHost } from "./app/remote/HostFileDialog";
import { setHostPicker } from "./platform/dialog";
import { getCurrentWebviewWindow } from "./platform/native";
import { initAppearance } from "./features/settings/model/appearance";
import { initSounds } from "./features/settings/model/sounds";
import { askQuitConfirmation } from "./app/model/appLifecycle";
import { homeDir } from "./platform/tauri/fs";
import { setHomeDir } from "./shared/lib/paths";
import { RemoteSessionClient } from "./app/remote/remoteSessions";
import { contentChangeEvents } from "./features/agents/model/mentorStore";
import { setRosterHost } from "./features/agents/model/agent";
import "lxgw-wenkai-screen-webfont/lxgwwenkaiscreen.css";
import "@fontsource-variable/literata/opsz.css";
import "./styles/index.css";

// Boot for a window connected to another device. Nothing of this device's own
// workspace is loaded: no mentor migration, no resumed turns, no agent CLIs.
initAppearance();
initSounds();
const client = new RemoteSessionClient(transport, {
  target: REMOTE_TARGET, applySettings: applyHostSettings, applyModels: applyHostModels,
  // Libraries, notes and courses shown from what this device kept are read from the host again.
  onReconnected: () => { for (const change of contentChangeEvents({})) window.dispatchEvent(change); },
});
// A shared setting saved here is the host's to keep; its answer comes back through the feed.
setHostSettingSink((key) => void client.setSetting(key, localStorage.getItem(key)));
// Files are chosen on the host, which is where they are read and written.
setHostPicker(pickOnHost);
// The roster here is a copy of the host's: a change goes to the host as the fields it changed.
setRosterHost({
  update: (agentId, changed, removed) => void client.intents["agent.update"](agentId, changed, removed).catch(() => undefined),
  reorder: (ids) => void client.intents["agent.reorder"]([...ids]).catch(() => undefined),
});
// Paths in the host's sessions are the host's, so `~/` means its home.
const stopWatching = client.subscribe(() => {
  if (client.getSnapshot().status.state !== "connected") return;
  stopWatching();
  void homeDir().then(setHomeDir).catch(() => undefined);
});
void client.start();
const workspaceLoaded = import("./app/remote/RemoteWorkspace");

// This window runs no turns and saves nothing, so it never holds up a quit.
void transport.listen<number>("quit_poll", ({ payload: id }) => {
  void transport.call("quit_poll_reply", { id, inFlight: 0 }).catch(() => undefined);
});
void getCurrentWebviewWindow().listen<{ id: number; inFlight: number }>("quit_confirm", ({ payload }) => {
  void askQuitConfirmation(payload.id, payload.inFlight);
});
void transport.listen<number>("quit_commit", ({ payload: id }) => {
  void transport.call("quit_ready", { id, persisted: true }).catch(() => undefined);
});

void workspaceLoaded.then(({ RemoteWorkspace }) => {
  ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
    <React.StrictMode>
      <BootGate>
        <RemoteWorkspace client={client} />
      </BootGate>
    </React.StrictMode>,
  );
});
