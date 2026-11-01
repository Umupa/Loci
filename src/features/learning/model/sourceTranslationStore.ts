import { invoke } from "@tauri-apps/api/core";
import { useEffect, useState } from "react";
import { findAgent } from "../../agents/model/agent";
import { parseTranslation, serializeTranslation, type SourceTranslation } from "./sourceTranslation";

/** Fired with `{ agentId, id, language }` when a translation is saved. */
export const SOURCE_TRANSLATION_EVENT = "loci:source-translation";

type Key = { agentId: string; id: string; language: string };

function folderOf(agentId: string): string {
  const folder = findAgent(agentId)?.folder;
  if (!folder) throw new Error("This mentor has no folder yet");
  return folder;
}

export async function loadSourceTranslation({ agentId, id, language }: Key): Promise<SourceTranslation> {
  const text = await invoke<string | null>("source_translation_read", { folder: folderOf(agentId), id, language });
  return text ? parseTranslation(language, text) : { language, units: [] };
}

export async function saveSourceTranslation({ agentId, id, language }: Key, translation: SourceTranslation): Promise<void> {
  await invoke("source_translation_write", { folder: folderOf(agentId), id, language, content: serializeTranslation(id, translation) });
  window.dispatchEvent(new CustomEvent<Key>(SOURCE_TRANSLATION_EVENT, { detail: { agentId, id, language } }));
}

/** A source's translation into a language, kept current as the mentor adds to it. */
export function useSourceTranslation(agentId: string | undefined, id: string, language: string | undefined): SourceTranslation | undefined {
  const [loaded, setLoaded] = useState<{ key: string; value: SourceTranslation }>();
  const key = agentId && language ? `${agentId}\n${id}\n${language}` : "";
  useEffect(() => {
    if (!agentId || !language) return;
    let live = true;
    const load = () => void loadSourceTranslation({ agentId, id, language })
      .then((value) => { if (live) setLoaded({ key, value }); }, () => { if (live) setLoaded({ key, value: { language, units: [] } }); });
    load();
    const changed = (event: Event) => {
      const detail = (event as CustomEvent<Key>).detail;
      if (detail.agentId === agentId && detail.id === id && detail.language === language) load();
    };
    window.addEventListener(SOURCE_TRANSLATION_EVENT, changed);
    return () => { live = false; window.removeEventListener(SOURCE_TRANSLATION_EVENT, changed); };
  }, [agentId, id, language, key]);
  return loaded?.key === key ? loaded.value : undefined;
}
