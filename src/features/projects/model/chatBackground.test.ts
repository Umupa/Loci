import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  pickAndSaveChatBackground,
  removeChatBackground,
} from "./chatBackground";

const mocks = vi.hoisted(() => ({
  invoke: vi.fn(),
  open: vi.fn(),
}));

vi.mock("@tauri-apps/api/core", () => ({
  convertFileSrc: (path: string) => `asset://${path}`,
  invoke: mocks.invoke,
}));

vi.mock("@tauri-apps/plugin-dialog", () => ({ open: mocks.open }));

describe("chat background image", () => {
  beforeEach(() => {
    mocks.invoke.mockReset();
    mocks.open.mockReset();
  });

  it("copies a picked image into app storage", async () => {
    mocks.open.mockResolvedValue("/Pictures/aurora.webp");
    mocks.invoke.mockResolvedValue(
      "/app-data/backgrounds/chat-background.webp",
    );

    await expect(pickAndSaveChatBackground()).resolves.toBe(
      "/app-data/backgrounds/chat-background.webp",
    );
    expect(mocks.invoke).toHaveBeenCalledWith("save_chat_background", {
      sourcePath: "/Pictures/aurora.webp",
    });
  });

  it("leaves the current background alone when picking is cancelled", async () => {
    mocks.open.mockResolvedValue(null);
    await expect(pickAndSaveChatBackground()).resolves.toBeNull();
    expect(mocks.invoke).not.toHaveBeenCalled();
  });

  it("removes the saved background", async () => {
    mocks.invoke.mockResolvedValue(undefined);
    await removeChatBackground();
    expect(mocks.invoke).toHaveBeenCalledWith("remove_chat_background");
  });
});
