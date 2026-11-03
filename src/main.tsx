import { bootWorkspaceReset } from "./platform/tauri/workspaceReset";
import { REMOTE_CLIENT } from "./platform/transport";

void bootWorkspaceReset().then((resetting) => {
  if (resetting) return;
  // A window showing another device's workspace boots without this device's sessions and mentors.
  if (REMOTE_CLIENT) void import("./remoteBootstrap");
  else void import("./bootstrap");
});
