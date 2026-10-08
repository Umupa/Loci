import { writeCanvasScene } from "./canvas";

/** Append to the persisted scene, flushing any editor draft before the write. */
export async function appendCanvasText(id: string, text: string) {
  const { convertToExcalidrawElements } = await import("@excalidraw/excalidraw");
  return writeCanvasScene(id, (current) => {
    const scene = JSON.parse(current.dataJson);
    const elements = scene.elements ?? [];
    const maxY = elements.reduce((bottom: number, element: { y: number; height: number; isDeleted?: boolean }) =>
      element.isDeleted ? bottom : Math.max(bottom, element.y + element.height), 0);
    const added = convertToExcalidrawElements([{ type: "text", x: 40, y: maxY + 40, text, fontSize: 16, width: 500 }]);
    return { dataJson: JSON.stringify({ ...scene, elements: [...elements, ...added] }) };
  });
}
