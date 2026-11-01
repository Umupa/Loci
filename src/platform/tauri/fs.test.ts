import { describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { listSkills, pickFolders, resolveProjectLocation, } from "./fs";
vi.mock("@tauri-apps/api/core", () => ({
    invoke: vi.fn(),
}));
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
describe("listSkills", () => {
    it("invokes list_skills with cwd and disabledPaths", async () => {
        vi.mocked(invoke).mockResolvedValueOnce([]);
        await listSkills("/repo", ["/repo/.agents/skills/review/SKILL.md"]);
        expect(invoke).toHaveBeenCalledWith("list_skills", {
            cwd: "/repo",
            disabledPaths: ["/repo/.agents/skills/review/SKILL.md"],
        });
    });
    it("passes null when disabledPaths is omitted", async () => {
        vi.mocked(invoke).mockResolvedValueOnce([]);
        await listSkills("/repo");
        expect(invoke).toHaveBeenCalledWith("list_skills", {
            cwd: "/repo",
            disabledPaths: null,
        });
    });
    it("asks for the user's own skills only for Settings", async () => {
        vi.mocked(invoke).mockResolvedValueOnce([]);
        await listSkills("~", null, true);
        expect(invoke).toHaveBeenCalledWith("list_skills", {
            cwd: "~",
            disabledPaths: null,
            userOnly: true,
        });
    });
});
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
