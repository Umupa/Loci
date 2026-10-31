import { useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";
import { handleAgentApp } from "../../features/agent-app/model/agentApp";
import { handleCanvasBridge } from "../../features/canvas/checkpoints";
import { agentForSession } from "../../features/agents/model/agent";
import type { CommandContext } from "../commands/context";
import { isAgentCommand, runCommand } from "../commands/dispatch";
import { commandFailure } from "../commands/registry";
import { agentAppHost, type AgentAppDeps } from "./agentAppHost";

export type { AppControlWorkspace } from "./agentAppHost";

type Options = AgentAppDeps & {
  /** The command layer `loci` reaches from a terminal; absent, terminal commands are refused. */
  commands?: CommandContext;
};
type ControlRequest = { id: string; namespace: string; sessionId: string; requestId: string; action: string; input: Record<string, unknown> };

/** Routes authenticated loopback requests into the same actions used by the UI. */
export function useAppControl(options: Options) {
  const latest = useRef(options);
  latest.current = options;
  const receipts = useRef(new Map<string, { signature: string; promise: Promise<unknown> }>());
  useEffect(() => {
    /** A retry with the same request ID gets the first call's answer and is not run twice. */
    const remember = (key: string, payload: ControlRequest, run: () => Promise<unknown>) => {
      const signature = JSON.stringify([payload.action, payload.input]);
      const previous = receipts.current.get(key);
      if (previous) {
        if (previous.signature !== signature) throw new Error("Request ID was already used with different input");
        return previous.promise;
      }
      let promise: Promise<unknown>;
      try { promise = run(); } catch (error) { promise = Promise.reject(error); }
      receipts.current.set(key, { signature, promise });
      void promise.catch(() => { if (receipts.current.get(key)?.promise === promise) receipts.current.delete(key); });
      if (receipts.current.size > 256) { const first = receipts.current.keys().next().value; if (first) receipts.current.delete(first); }
      return promise;
    };
    const listening = getCurrentWebviewWindow().listen<ControlRequest>("loci-control-request", ({ payload }) => {
      const handle = async () => {
        const { workspace, runtime, submission, delegation, commands } = latest.current;
        // A terminal outside Loci, authenticated by the host with the local token.
        if (payload.namespace === "cli") {
          if (!commands) throw new Error("This window does not run terminal commands");
          return remember(`cli:${payload.requestId}`, payload, () =>
            runCommand(commands, payload.action, payload.input, { requestId: payload.requestId, caller: "external" }));
        }
        const source = runtime.sessionsRef.current.find((session) => session.id === payload.sessionId);
        // The built-in Excalidraw MCP server reaches canvases here; it needs no app access grant.
        if (payload.namespace === "canvas") {
          if (!source) throw new Error("This session cannot draw on Loci canvases");
          return handleCanvasBridge(source, payload.action, payload.input, { isOpen: workspace.isCanvasOpen, reveal: workspace.revealCanvas });
        }
        if (payload.namespace !== "app") throw new Error("Unknown CLI namespace");
        if (!source) throw new Error("This session cannot use the Loci app CLI");
        return remember(`${source.id}:${payload.requestId}`, payload, () => {
          // The command layer's mentor commands (such as reader.*) for the mentor's own turn.
          if (commands && isAgentCommand(payload.action)) {
            const agentId = agentForSession(source.id)?.id;
            if (!agentId) throw new Error("Only a mentor's own conversation can use this action");
            return runCommand(commands, payload.action, payload.input, { requestId: payload.requestId, caller: "agent", agentId });
          }
          return handleAgentApp(source, payload.requestId, payload.action, payload.input, agentAppHost(source, { workspace, runtime, submission, delegation }));
        });
      };
      void handle().then(
        (result) => invoke("control_reply", { id: payload.id, response: { ok: true, result } }),
        (error: unknown) => {
          // A terminal is told why with a stable code; agents keep the reply they always had.
          const response = payload.namespace === "cli"
            ? { ok: false, ...commandFailure(error) }
            : { ok: false, error: error instanceof Error ? error.message : String(error) };
          return invoke("control_reply", { id: payload.id, response });
        },
      ).catch(console.error);
    });
    // Commands from a terminal outside Loci are sent only to windows that listen.
    void listening.then(() => invoke("control_window_ready")).catch(console.error);
    return () => { void listening.then((stop) => stop()); };
  }, []);
}
