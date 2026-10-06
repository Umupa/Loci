// @vitest-environment happy-dom
import { beforeEach, expect, it } from "vitest";
import { knownNotificationProject, knownNotificationProjectSelection, } from "./notificationProjects";
beforeEach(() => localStorage.clear());
it("derives local notification identity immediately from the normalized path", () => {
    expect(knownNotificationProject("C:/Work/App")).toEqual({
        id: "local:c:/work/app",
        name: "App",
        detail: "C:/Work/App",
        kind: "local",
        paths: ["C:/Work/App"],
    });
    expect(knownNotificationProject("c:\\work\\app")?.id).toBe("local:c:/work/app");
});
it("keeps separate folder paths as separate projects", () => {
    const selection = knownNotificationProjectSelection([
        "/work/app",
        "/work/app-review",
    ]);
    expect(selection.projects.map((project) => project.id)).toEqual([
        "local:/work/app",
        "local:/work/app-review",
    ]);
});
