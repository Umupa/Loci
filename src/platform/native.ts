// Tauri APIs that act on the device showing the app (its window, webview,
// browser, updater), so they never go through the transport. File pickers and
// confirmations live in `./dialog`.
// `convertFileSrc` is for files on this device; another device's go through `transport.fileUrl`.
export { convertFileSrc, isTauri } from "@tauri-apps/api/core";
export { getIdentifier, getName, getVersion } from "@tauri-apps/api/app";
export { getCurrentWindow } from "@tauri-apps/api/window";
export { getCurrentWebview, type DragDropEvent } from "@tauri-apps/api/webview";
export { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";
export { openUrl } from "@tauri-apps/plugin-opener";
export { relaunch } from "@tauri-apps/plugin-process";
export { check, type Update } from "@tauri-apps/plugin-updater";
