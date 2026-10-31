import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";

export async function pickAndSaveChatBackground(title = "Choose chat background"): Promise<string | null> {
  const sourcePath = await open({
    multiple: false,
    directory: false,
    title,
    filters: [
      {
        name: "Images",
        extensions: ["png", "jpg", "jpeg", "gif", "webp"],
      },
    ],
  });
  if (typeof sourcePath !== "string" || !sourcePath) return null;
  return invoke<string>("save_chat_background", { sourcePath });
}

export function removeChatBackground(): Promise<void> {
  return invoke<void>("remove_chat_background");
}
