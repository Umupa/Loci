import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const free = new Set(["read", "grep", "find", "ls"]);

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (free.has(event.toolName)) return undefined;
    const allowed = await ctx.ui.confirm(
      "loci:permission",
      JSON.stringify({ toolCallId: event.toolCallId, toolName: event.toolName }),
    );
    return allowed ? undefined : { block: true, reason: "The user did not allow this." };
  });
}
