import { transport } from "../../../platform/transport";
import { openOnThisDevice as open } from "../../../platform/dialog";

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
  return transport.call<string>("save_chat_background", { sourcePath });
}

export function removeChatBackground(): Promise<void> {
  return transport.call<void>("remove_chat_background");
}
