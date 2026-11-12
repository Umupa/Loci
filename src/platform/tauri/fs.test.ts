import { describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { resolveProjectLocation } from "./fs";
vi.mock("@tauri-apps/api/core", () => ({
    invoke: vi.fn(),
}));
describe("resolveProjectLocation", () => {
    it("passes the saved filesystem identity to the backend", async () => {
        vi.mocked(invoke).mockResolvedValueOnce({
            path: "/repo-renamed",
            identity: "unix:1:2",
        });
        await expect(resolveProjectLocation("/repo", "unix:1:2")).resolves.toEqual({
            path: "/repo-renamed",
            identity: "unix:1:2",
        });
        expect(invoke).toHaveBeenCalledWith("resolve_project_location", {
            path: "/repo",
            identity: "unix:1:2",
        });
    });
    it("uses null until the project has a saved identity", async () => {
        vi.mocked(invoke).mockResolvedValueOnce(null);
        await resolveProjectLocation("/repo");
        expect(invoke).toHaveBeenCalledWith("resolve_project_location", {
            path: "/repo",
            identity: null,
        });
    });
});
