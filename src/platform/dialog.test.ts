import { describe, expect, it, vi } from "vitest";
import { open } from "@tauri-apps/plugin-dialog";
import { pickFolders } from "./dialog";
vi.mock("@tauri-apps/plugin-dialog", () => ({
    open: vi.fn(),
}));
describe("pickFolders", () => {
    it("returns every folder chosen in one pass", async () => {
        vi.mocked(open).mockResolvedValueOnce(["/a/one", "/a/two"]);
        await expect(pickFolders()).resolves.toEqual(["/a/one", "/a/two"]);
        expect(vi.mocked(open).mock.calls[0]?.[0]).toMatchObject({
            directory: true,
            multiple: true,
        });
    });
    it("handles the dialog returning a bare string for a single folder", async () => {
        vi.mocked(open).mockResolvedValueOnce("/a/only");
        await expect(pickFolders()).resolves.toEqual(["/a/only"]);
    });
    it("returns nothing when the dialog is dismissed", async () => {
        vi.mocked(open).mockResolvedValueOnce(null);
        await expect(pickFolders()).resolves.toEqual([]);
    });
});
