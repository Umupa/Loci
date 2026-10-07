import { invoke } from "@tauri-apps/api/core";
import { looksLikeProject, sameProjectPath } from "../projects/model/recents";
import type { Session } from "../sessions/model/session";
import { checkpointCanvasId, createEmptyCanvas, getCanvas, loadCanvases, readCanvasScene, upsertCanvas, writeCanvasScene, type Canvas } from "./canvas";

/** What the canvas bridge needs from the window it runs in. */
export type CanvasBridgeHost = {
  /** Whether a pane already shows this drawing. */
  isOpen(canvasId: string): boolean;
  /** Show a drawing beside the session that drew on it, without taking focus. A no-op when it is already there. */
  reveal(canvasId: string, sessionId: string): void;
};

type LatestCheckpoint = { checkpointId: string; canvasId: string; baselineJson: string; createdAt: number };

const CHECKPOINT_ID = /^[A-Za-z0-9_-]{1,128}$/;
const FIELDS: Record<string, readonly string[]> = {
  "checkpoint.load": ["id"],
  "checkpoint.save": ["id", "baseId", "deletedIds", "elements", "replace"],
  "context.read": ["id"],
};

function checkpointId(value: unknown, name: string): string {
  if (typeof value !== "string" || !CHECKPOINT_ID.test(value)) throw new Error(`${name} must be a checkpoint id`);
  return value;
}

function projectOf(source: Session): string {
  if (!looksLikeProject(source.cwd)) throw new Error("Choose a project folder in this session before drawing");
  return source.cwd;
}

/** A checkpoint only opens drawings of the calling session's project. */
async function checkpointCanvas(source: Session, id: string): Promise<Canvas | null> {
  const cwd = projectOf(source);
  const canvasId = await checkpointCanvasId(id);
  const canvas = canvasId ? await getCanvas(canvasId) : null;
  return canvas?.cwd && sameProjectPath(canvas.cwd, cwd) ? canvas : null;
}

// Parallel tool calls on one drawing must each see the other's result.
const saving = new Map<string, Promise<unknown>>();
function inOrder<T>(canvasId: string, task: () => Promise<T>): Promise<T> {
  const run = (saving.get(canvasId) ?? Promise.resolve()).then(task, task);
  saving.set(canvasId, run);
  void run.catch(() => undefined).finally(() => { if (saving.get(canvasId) === run) saving.delete(canvasId); });
  return run;
}

/**
 * Loci's side of the official Excalidraw MCP server's checkpoint store, plus
 * the host tool that lets an agent read a drawing. Every checkpoint id of a
 * drawing loads that drawing as it is now; a save applies the call's changes.
 */
export async function handleCanvasBridge(source: Session, action: string, input: Record<string, unknown>, host: CanvasBridgeHost): Promise<unknown> {
  const allowed = FIELDS[action];
  if (!allowed) throw new Error(`Unknown canvas action: ${action}`);
  const unknown = Object.keys(input).filter((key) => !allowed.includes(key));
  if (unknown.length) throw new Error(`Unknown ${action} fields: ${unknown.join(", ")}`);
  const scenes = await import("./checkpointScene");

  switch (action) {
    case "checkpoint.load": {
      const canvas = await checkpointCanvas(source, checkpointId(input.id, "id"));
      const saved = canvas && await readCanvasScene(canvas.id);
      return saved ? { elements: scenes.checkpointElements(saved.dataJson) } : null;
    }
    case "checkpoint.save": {
      const cwd = projectOf(source);
      const id = checkpointId(input.id, "id");
      if (!Array.isArray(input.elements)) throw new Error("elements must be an array");
      if (input.deletedIds !== undefined && (!Array.isArray(input.deletedIds) || input.deletedIds.some((entry) => typeof entry !== "string")))
        throw new Error("deletedIds must be an array of element ids");
      const patch = { elements: input.elements, deletedIds: input.deletedIds as string[] | undefined, replace: input.replace === true };
      const baseId = input.baseId === undefined ? undefined : checkpointId(input.baseId, "baseId");
      // A repeated id is the same drawing: the official widget re-saves its checkpoint.
      const target = await checkpointCanvas(source, baseId ?? id);
      if (!target && (baseId || patch.replace)) throw new Error(`Checkpoint "${baseId ?? id}" was not found in this project`);
      if (!target) {
        const scene = scenes.applyCheckpointPatch("", patch);
        const canvas = await upsertCanvas({
          ...createEmptyCanvas(cwd),
          title: scenes.suggestedTitle(scene.dataJson) ?? "Untitled drawing",
          dataJson: scene.dataJson,
          checkpoint: { id, baselineJson: scenes.checkpointBaseline(scene.dataJson) },
        });
        host.reveal(canvas.id, source.id);
        return { canvasId: canvas.id, title: canvas.title, created: true };
      }
      const canvas = await inOrder(target.id, () => writeCanvasScene(target.id, (current) => {
        const scene = scenes.applyCheckpointPatch(current.dataJson, patch);
        return { ...scene, checkpoint: { id, baselineJson: scenes.checkpointBaseline(scene.dataJson) } };
      }));
      host.reveal(canvas.id, source.id);
      return { canvasId: canvas.id, title: canvas.title, created: false };
    }
    case "context.read": {
      const cwd = projectOf(source);
      if (input.id === undefined) {
        const drawings = (await loadCanvases(true))
          .filter((canvas) => !!canvas.cwd && sameProjectPath(canvas.cwd, cwd))
          .sort((a, b) => b.updatedAt - a.updatedAt)
          .map((canvas) => ({ checkpointId: canvas.id, title: canvas.title, updatedAt: new Date(canvas.updatedAt).toISOString(),
            elements: scenes.checkpointElements(canvas.dataJson).length, open: host.isOpen(canvas.id) }));
        return { text: drawings.length
          ? `Drawings in this Loci project, newest first. "open" ones are on screen. Read one by passing its checkpointId.\n${JSON.stringify(drawings)}`
          : "This Loci project has no drawings yet. Call create_view to make one." };
      }
      const id = checkpointId(input.id, "id");
      const canvas = await checkpointCanvas(source, id);
      const saved = canvas && await readCanvasScene(canvas.id);
      if (!saved) throw new Error(`Checkpoint "${id}" was not found in this project. Call read_widget_context without checkpointId to list drawings.`);
      const latest = await invoke<LatestCheckpoint | null>("canvas_checkpoint_latest", { canvasId: saved.id });
      const edits = latest?.baselineJson ? scenes.describeUserEdits(latest.baselineJson, saved.dataJson, id) : "";
      const files = Object.keys((JSON.parse(saved.dataJson) as { files?: object }).files ?? {}).length;
      return { text: [
        `Drawing "${saved.title}" as it is now in Loci.`,
        edits || (latest ? "The user has not edited it since the last create_view call." : "The user drew this by hand; no agent has edited it yet."),
        `To change it, call create_view with elements starting with {"type":"restoreCheckpoint","id":"${id}"}, then only new elements and {"type":"delete","ids":"<id>,<id>"} entries. Elements you do not delete stay as they are.`,
        files ? `It holds ${files} image file(s); keep an image by not deleting its element.` : "",
        `Current elements:\n${JSON.stringify(scenes.compactElements(saved.dataJson))}`,
      ].filter(Boolean).join("\n") };
    }
  }
}
