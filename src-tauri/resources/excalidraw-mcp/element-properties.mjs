// Shared by the MCP tool schema and the window's authoritative validation.
const number = { type: "number" };
const positive = { type: "number", exclusiveMinimum: 0 };
const choices = (values) => ({ type: "string", enum: values });
export const ELEMENT_PROPERTIES = {
  x: number, y: number, width: positive, height: positive, angle: { ...number, description: "Rotation in radians" },
  strokeColor: { type: "string", minLength: 1, maxLength: 128 },
  backgroundColor: { type: "string", minLength: 1, maxLength: 128 },
  fillStyle: choices(["solid", "hachure", "cross-hatch", "zigzag"]),
  strokeWidth: { type: "number", minimum: 0 },
  strokeStyle: choices(["solid", "dashed", "dotted"]),
  roughness: { type: "number", minimum: 0, maximum: 2 },
  opacity: { type: "number", minimum: 0, maximum: 100 },
  locked: { type: "boolean" },
  text: { type: "string", minLength: 1, maxLength: 100000 },
  fontSize: positive,
  fontFamily: { type: "integer", enum: [1, 2, 3, 5, 6, 7, 8, 9] },
  textAlign: choices(["left", "center", "right"]),
  verticalAlign: choices(["top", "middle", "bottom"]),
  lineHeight: positive,
  autoResize: { type: "boolean" },
  name: { type: "string", maxLength: 1000 },
  scale: { type: "array", minItems: 2, maxItems: 2, items: { type: "number", enum: [-1, 1] } },
};
export const ELEMENT_UPDATES_SCHEMA = {
  type: "array", minItems: 1, maxItems: 500,
  items: {
    type: "object", required: ["id", "changes"], additionalProperties: false,
    properties: {
      id: { type: "string", minLength: 1, maxLength: 256 },
      changes: { type: "object", minProperties: 1, additionalProperties: false, properties: ELEMENT_PROPERTIES },
    },
  },
};
const textFields = new Set(["text", "fontSize", "fontFamily", "textAlign", "verticalAlign", "lineHeight", "autoResize"]);
const record = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
function valueAllowed(value, schema) {
  if (schema.type === "array") return Array.isArray(value) && value.length === 2 && value.every(v => valueAllowed(v, schema.items));
  if (schema.type === "integer") { if (!Number.isInteger(value)) return false; }
  else if (typeof value !== schema.type) return false;
  if (typeof value === "number" && (!Number.isFinite(value) ||
      (schema.minimum !== undefined && value < schema.minimum) ||
      (schema.exclusiveMinimum !== undefined && value <= schema.exclusiveMinimum) ||
      (schema.maximum !== undefined && value > schema.maximum))) return false;
  if (typeof value === "string" && ((schema.minLength && value.length < schema.minLength) || value.length > (schema.maxLength ?? Infinity))) return false;
  return !schema.enum || schema.enum.includes(value);
}
/** Validate the whole batch before changing anything; callers never create or delete elements. */
export function validateElementUpdates(updates, elements) {
  if (!Array.isArray(updates) || !updates.length || updates.length > 500) throw new Error("updates must contain 1 to 500 existing element changes");
  const byId = new Map(elements.filter(el => !el.isDeleted).map(el => [el.id, el]));
  const seen = new Set();
  for (const update of updates) {
    if (!record(update) || Object.keys(update).some(key => key !== "id" && key !== "changes") ||
        typeof update.id !== "string" || !update.id.length || update.id.length > 256 || !record(update.changes) || !Object.keys(update.changes).length)
      throw new Error("Each update needs an existing id and a non-empty changes object");
    const element = byId.get(update.id);
    if (!element) throw new Error(`Element "${update.id}" does not exist in this drawing`);
    if (seen.has(update.id)) throw new Error(`Duplicate element update: ${update.id}`);
    seen.add(update.id);
    for (const [key, value] of Object.entries(update.changes)) {
      if (!Object.hasOwn(ELEMENT_PROPERTIES, key)) throw new Error(`Cannot update ${key}; IDs, types, image files and binding targets are preserved`);
      if (!valueAllowed(value, ELEMENT_PROPERTIES[key])) throw new Error(`Invalid ${key} for element "${update.id}"`);
      if (key === "text" && !value.trim()) throw new Error("Text must not be blank; update_elements never removes elements");
      if (textFields.has(key) && element.type !== "text") throw new Error(`${key} only applies to text elements`);
      if (key === "name" && element.type !== "frame" && element.type !== "magicframe") throw new Error("name only applies to frames");
      if (key === "scale" && element.type !== "image") throw new Error("scale only applies to images");
      if (element.type === "text" && key === "height") throw new Error("Text height is measured from fontSize and lineHeight");
    }
  }
  return updates;
}
