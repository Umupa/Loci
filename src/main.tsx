import { bootWorkspaceReset } from "./platform/tauri/workspaceReset";

void bootWorkspaceReset().then((resetting) => {
  if (!resetting) void import("./bootstrap");
});
