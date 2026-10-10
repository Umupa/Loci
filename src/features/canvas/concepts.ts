import { writeCanvasScene } from "./canvas";
import { applyElementUpdates } from "./elementUpdates";
import { isRecord } from "./scene";

const conceptColors = {
  untouched: "#f4f4f5",
  learning: "#fef3c7",
  mastered: "#dcfce7",
} as const;

/** Update the persisted drawing too, including when its pane is closed. */
export async function setConceptStatus(
  canvasId: string,
  courseId: string,
  itemId: string,
  status: keyof typeof conceptColors,
  agentId?: string,
): Promise<void> {
  await writeCanvasScene(canvasId, (current) => {
    const scene = JSON.parse(current.dataJson) as { elements: Array<Record<string, unknown>> };
    const updates = scene.elements.filter((element) => {
      const data = element.customData;
      return !element.isDeleted && isRecord(data) && data.type === "concept" &&
        data.courseId === courseId && data.conceptId === itemId &&
        (data.agentId === undefined || data.agentId === agentId);
    }).map((element) => ({ id: element.id, changes: { backgroundColor: conceptColors[status] } }));
    if (!updates.length) throw new Error("The drawing has no matching concept node.");
    // writeCanvasScene flushes/rebases user drafts and retries against the saved
    // revision. A derived progress color should not add an editor undo step.
    return { dataJson: applyElementUpdates(current.dataJson, updates).dataJson, silent: true };
  });
}
