import React from "react";
import ReactDOM from "react-dom/client";
import { transport } from "./platform/transport";
import { getCurrentWebviewWindow } from "./platform/native";
import { initAppearance } from "./features/settings/model/appearance";
import { initSounds } from "./features/settings/model/sounds";
import {
  abortQuit,
  askQuitConfirmation,
  commitQuit,
  loadBootWorkspace,
  reportQuitPoll,
} from "./app/model/appLifecycle";
import { homeDir } from "./platform/tauri/fs";
import { setHomeDir } from "./shared/lib/paths";
import { initializeProviderBinaryPaths } from "./features/providers/model/providerBinaryPaths";
import { hydrateMentors } from "./features/agents/model/mentorStore";
import { BootGate } from "./bootSplash";
import "./styles/index.css";

performance.mark("loci:bootstrap");
// Let local boot IPC overlap loading/evaluating the workspace UI.
const appLoaded = import("./app/App");

initAppearance();
initSounds();
// Prime the real home directory before the first render so every `~/` file
// reference resolves consistently. The IPC call is local and failures remain
// best-effort, falling back to inference from a session's cwd.
const homeDirPrimed = homeDir()
  .then(setHomeDir)
  .catch(() => {});
const providerBinaryPathsPrimed = initializeProviderBinaryPaths().catch(
  () => undefined,
);
// Mentors' folders: migrate 0.3 data once, then load the roster from them.
const mentorsHydrated = hydrateMentors().catch(() => undefined);

void transport.listen<number>("quit_poll", (event) => {
  void reportQuitPoll(event.payload);
});
// Scoped to this window on purpose: a global `listen` is registered as `Any`,
// which Tauri matches for every event regardless of the emitter's target, so
// one dialog would become one per window.
void getCurrentWebviewWindow().listen<{ id: number; inFlight: number }>(
  "quit_confirm",
  (event) => {
    void askQuitConfirmation(event.payload.id, event.payload.inFlight);
  },
);
void transport.listen<number>("quit_commit", (event) => {
  void commitQuit(event.payload);
});
void transport.listen("quit_aborted", () => {
  abortQuit();
});

void Promise.all([
  homeDirPrimed,
  providerBinaryPathsPrimed,
  mentorsHydrated,
  loadBootWorkspace(),
  appLoaded,
]).then(
  ([
    ,
    ,
    ,
    { resumed },
    { default: App },
  ]) => {
    performance.mark("loci:workspace-ready");
    ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
      <React.StrictMode>
        <BootGate>
          <App resumed={resumed} />
        </BootGate>
      </React.StrictMode>,
    );
  },
);
