export const ELEMENT_PROPERTIES: Record<string, Record<string, unknown>>;
export const ELEMENT_UPDATES_SCHEMA: Record<string, unknown>;
export function validateElementUpdates(updates: unknown, elements: readonly { id: string; type: string; isDeleted?: boolean }[]): Array<{ id: string; changes: Record<string, unknown> }>;
