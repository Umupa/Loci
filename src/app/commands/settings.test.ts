// @vitest-environment happy-dom
import { beforeEach, describe, expect, it } from "vitest";
import { loadNewAgentAccess } from "../../features/agents/model/agentAccess";
import { loadCanvasMcpEnabled } from "../../features/settings/model/builtinMcp";
import { loadLastModelChoice } from "../../features/sessions/model/models";
import { runCommand } from "./dispatch";
import { testContext } from "./testContext";

const external = { requestId: "r1", caller: "external" as const };
beforeEach(() => localStorage.clear());

describe("settings commands", () => {
  it("read and change the allowed settings as Settings does", async () => {
    const { ctx } = testContext();
    expect(await runCommand(ctx, "settings.get", {}, external)).toMatchObject({ defaultProvider: "claude", canvasTools: true });
    await runCommand(ctx, "settings.set", { key: "defaultProvider", value: "agy" }, external);
    expect(loadLastModelChoice()?.harness).toBe("antigravity");
    expect(await runCommand(ctx, "settings.get", { key: "defaultProvider" }, external)).toEqual({ defaultProvider: "antigravity" });
    await runCommand(ctx, "settings.set", { key: "canvasTools", value: "false" }, external);
    expect(loadCanvasMcpEnabled()).toBe(false);
    expect(await runCommand(ctx, "settings.get", { key: "defaultMentorAccess" }, external)).toEqual({ defaultMentorAccess: "full-access" });
    await runCommand(ctx, "settings.set", { key: "defaultMentorAccess", value: "auto" }, external);
    expect(loadNewAgentAccess()).toBe("auto");
    await expect(runCommand(ctx, "settings.set", { key: "defaultMentorAccess", value: "yolo" }, external)).rejects.toMatchObject({ code: "usage" });
  });

  it("refuse anything else", async () => {
    const { ctx } = testContext();
    await expect(runCommand(ctx, "settings.set", { key: "theme", value: "dark" }, external)).rejects.toMatchObject({ code: "usage" });
    await expect(runCommand(ctx, "settings.set", { key: "canvasTools", value: "maybe" }, external)).rejects.toMatchObject({ code: "usage" });
    await expect(runCommand(ctx, "settings.set", { key: "defaultModel", value: "no-such-model" }, external)).rejects.toMatchObject({ code: "usage" });
  });

  it("set the learning language mentors write in", async () => {
    const { ctx } = testContext();
    expect(await runCommand(ctx, "settings.get", { key: "learningLanguage" }, external)).toEqual({ learningLanguage: "auto" });
    await runCommand(ctx, "settings.set", { key: "learningLanguage", value: "zh-CN" }, external);
    expect(localStorage.getItem("loci.learningLanguage")).toBe("zh-CN");
    await expect(runCommand(ctx, "settings.set", { key: "learningLanguage", value: "fr" }, external)).rejects.toMatchObject({ code: "usage" });
  });
});
