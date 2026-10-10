import { invoke } from "@tauri-apps/api/core";
import type { AgentDocument } from "../../sessions/model/cards";

/** A document in an agent's library, as the store lists it. */
export type StoredDocument = {
  id: string;
  title: string;
  subject?: string | null;
  /** Present when one document is read; listings only name them. */
  body?: string;
  /** Where a source was published. A document with one is someone else's text, kept as saved. */
  sourceUrl?: string | null;
  sourceVersion?: string | null;
  fetchedAt?: number | null;
  createdAt: number;
  updatedAt: number;
};

const DOCUMENTS_CHANGED = "loci:agent-documents-changed";

function changed(): void {
  window.dispatchEvent(new CustomEvent(DOCUMENTS_CHANGED));
}

export function subscribeAgentDocuments(onChange: () => void): () => void {
  window.addEventListener(DOCUMENTS_CHANGED, onChange);
  return () => window.removeEventListener(DOCUMENTS_CHANGED, onChange);
}

/** Everything the agent has written for the user, newest first, without the text. */
export function listAgentDocuments(agentId: string): Promise<StoredDocument[]> {
  return invoke<StoredDocument[]>("agent_documents_list", { agent: agentId });
}

export async function readAgentDocument(
  agentId: string,
  id: string,
): Promise<StoredDocument | undefined> {
  return (
    (await invoke<StoredDocument | null>("agent_documents_get", {
      agent: agentId,
      id,
    })) ?? undefined
  );
}

/** Saves what a reply wrote. The same id again is a revision of that document. */
export async function saveAgentDocuments(
  agentId: string,
  documents: readonly AgentDocument[],
): Promise<void> {
  if (!documents.length) return;
  for (const document of documents) {
    await invoke("agent_documents_upsert", {
      agent: agentId,
      document: {
        id: document.id,
        title: document.title,
        subject: document.subject ?? null,
        body: document.body,
      },
    });
  }
  changed();
}

/** Takes a saved file into the library as a source: its text exactly as the file holds it. */
export async function importAgentSource(
  agentId: string,
  source: { id: string; title: string; subject?: string; path: string; sourceUrl: string; version?: string },
): Promise<StoredDocument> {
  const saved = await invoke<StoredDocument>("agent_documents_import", {
    agent: agentId,
    source: { ...source, subject: source.subject ?? null, version: source.version ?? null },
  });
  changed();
  return saved;
}

/** Removes one document, or with no id everything an agent wrote. */
export async function deleteAgentDocument(
  agentId: string,
  id?: string,
): Promise<void> {
  await invoke("agent_documents_delete", { agent: agentId, id: id ?? null });
  changed();
}
