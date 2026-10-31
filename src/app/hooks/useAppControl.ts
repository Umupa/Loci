import { useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";
import { handleAgentApp } from "../../features/agent-app/model/agentApp";
import { handleCanvasBridge } from "../../features/canvas/checkpoints";
import { agentAppHost, type AgentAppDeps } from "./agentAppHost";

export type { AppControlWorkspace } from "./agentAppHost";

type Options = AgentAppDeps;
type ControlRequest = { id: string; namespace: string; sessionId: string; requestId: string; action: string; input: Record<string, unknown> };

/** Routes authenticated loopback requests into the same actions used by the UI. */
export function useAppControl(options: Options) {
  const latest = useRef(options);
  latest.current = options;
  const receipts = useRef(new Map<string, { signature: string; promise: Promise<unknown> }>());
  useEffect(() => {
    const listening = getCurrentWebviewWindow().listen<ControlRequest>("loci-control-request", ({ payload }) => {
      const handle = async () => {
        const { workspace, runtime, submission, delegation } = latest.current;
        const source = runtime.sessionsRef.current.find((session) => session.id === payload.sessionId);
        // The built-in Excalidraw MCP server reaches canvases here; it needs no app access grant.
        if (payload.namespace === "canvas") {
          if (!source) throw new Error("This session cannot draw on Loci canvases");
          return handleCanvasBridge(source, payload.action, payload.input, { isOpen: workspace.isCanvasOpen, reveal: workspace.revealCanvas });
        }
        if (payload.namespace !== "app") throw new Error("Unknown CLI namespace");
        if (!source) throw new Error("This session cannot use the Loci app CLI");
        const key = `${source.id}:${payload.requestId}`;
        const signature = JSON.stringify([payload.action, payload.input]);
        const previous = receipts.current.get(key);
        if (previous) {
          if (previous.signature !== signature) throw new Error("Request ID was already used with different input");
          return previous.promise;
        }
        const promise = handleAgentApp(source, payload.requestId, payload.action, payload.input, agentAppHost(source, { workspace, runtime, submission, delegation }));
        receipts.current.set(key, { signature, promise });
        void promise.catch(() => { if (receipts.current.get(key)?.promise === promise) receipts.current.delete(key); });
        if (receipts.current.size > 256) { const first = receipts.current.keys().next().value; if (first) receipts.current.delete(first); }
        return promise;
      };
      void handle().then(
        (result) => invoke("control_reply", { id: payload.id, response: { ok: true, result } }),
        (error: unknown) => invoke("control_reply", { id: payload.id, response: { ok: false, error: error instanceof Error ? error.message : String(error) } }),
      ).catch(console.error);
    });
    return () => { void listening.then((stop) => stop()); };
  }, []);
}
