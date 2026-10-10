import { invoke } from "@tauri-apps/api/core";
import type { JsonValue, LearningSource, PdfAnnotation, ReadingDocument, StoredWidget, WidgetOwner, WidgetRef, WidgetSpec } from "./types";

export const LEARNING_CHANGED_EVENT = "loci:learning-changed";
function changed() { window.dispatchEvent(new Event(LEARNING_CHANGED_EVENT)); }
export function subscribeLearningChanges(listener: () => void) {
  window.addEventListener(LEARNING_CHANGED_EVENT, listener);
  return () => window.removeEventListener(LEARNING_CHANGED_EVENT, listener);
}
async function write<T>(command: string, input: Record<string, unknown>): Promise<T> {
  const result = await invoke<T>(command, input);
  changed();
  return result;
}

export const registerLearningSource = (source: LearningSource) => write<LearningSource>("learning_source_register", { source });
export const getLearningSource = (id: string) => invoke<LearningSource | null>("learning_source_get", { id });
export const registerReadingDocument = (path: string, fingerprint: string, title: string) => write<ReadingDocument>("learning_document_register", { path, fingerprint, title });
export const getReadingDocument = (id: string) => invoke<ReadingDocument | null>("learning_document_get", { id });
export const getReadingDocumentByPath = (path: string) => invoke<ReadingDocument | null>("learning_document_find", { path });
export const relocateReadingDocument = (id: string, path: string, fingerprint: string) => write<ReadingDocument>("learning_document_relocate", { id, path, fingerprint });
export const listPdfAnnotations = (documentId: string) => invoke<PdfAnnotation[]>("learning_annotations_list", { documentId });
export const upsertPdfAnnotation = (annotation: PdfAnnotation) => write<PdfAnnotation>("learning_annotation_upsert", { annotation });
export const deletePdfAnnotation = (id: string) => write<void>("learning_annotation_delete", { id });
export const linkAnnotationDiscussion = (id: string, sessionId: string, blockId: string) => write<void>("learning_annotation_link", { id, sessionId, blockId });
export const upsertLearningWidget = (owner: WidgetOwner, spec: WidgetSpec, sourceSessionId: string, sourceBlockId: string, sourceAt = Date.now()) => write<StoredWidget>("learning_widget_upsert", { owner, spec, sourceSessionId, sourceBlockId, sourceAt });
export const getLearningWidget = (ref: WidgetRef) => invoke<StoredWidget | null>("learning_widget_get", { widget: ref });
export const listLearningWidgets = (owner: WidgetOwner, savedOnly = true) => invoke<StoredWidget[]>("learning_widgets_list", { owner, savedOnly });
export const setLearningWidgetSaved = (ref: WidgetRef, saved: boolean) => write<StoredWidget>("learning_widget_save", { widget: ref, saved });
export const setLearningWidgetState = (ref: WidgetRef, state: JsonValue) => write<void>("learning_widget_state", { widget: ref, state });
export const deleteOwnerWidgets = (owner: WidgetOwner) => write<void>("learning_widgets_delete_owner", { owner });
