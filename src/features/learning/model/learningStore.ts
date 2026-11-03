import { transport } from "../../../platform/transport";
import type { Annotation, AnnotationTarget, LearningSource, PdfAnnotation, ReadingDocument } from "./types";

export const LEARNING_CHANGED_EVENT = "loci:learning-changed";
function changed() { window.dispatchEvent(new Event(LEARNING_CHANGED_EVENT)); }
export function subscribeLearningChanges(listener: () => void) {
  window.addEventListener(LEARNING_CHANGED_EVENT, listener);
  return () => window.removeEventListener(LEARNING_CHANGED_EVENT, listener);
}
async function write<T>(command: string, input: Record<string, unknown>): Promise<T> {
  const result = await transport.call<T>(command, input);
  changed();
  return result;
}

export const registerLearningSource = (source: LearningSource) => write<LearningSource>("learning_source_register", { source });
export const getLearningSource = (id: string) => transport.call<LearningSource | null>("learning_source_get", { id });
export const registerReadingDocument = (path: string, fingerprint: string, title: string) => write<ReadingDocument>("learning_document_register", { path, fingerprint, title });
export const getReadingDocument = (id: string) => transport.call<ReadingDocument | null>("learning_document_get", { id });
export const getReadingDocumentByPath = (path: string) => transport.call<ReadingDocument | null>("learning_document_find", { path });
export const relocateReadingDocument = (id: string, path: string, fingerprint: string) => write<ReadingDocument>("learning_document_relocate", { id, path, fingerprint });
export const listPdfAnnotations = (documentId: string) => transport.call<PdfAnnotation[]>("learning_annotations_list", { documentId });
export const upsertPdfAnnotation = (annotation: PdfAnnotation) => write<PdfAnnotation>("learning_annotation_upsert", { annotation });
export const deletePdfAnnotation = (id: string) => write<void>("learning_annotation_delete", { id });
export const linkAnnotationDiscussion = (id: string, sessionId: string, blockId: string) => write<void>("learning_annotation_link", { id, sessionId, blockId });
export const listAnnotations = (target: AnnotationTarget) => transport.call<Annotation[]>("learning_annotations_for", { target });
/** Marks on several targets in one call, as a course's lessons need them. */
export const queryAnnotations = (targets: AnnotationTarget[]) => targets.length ? transport.call<Annotation[]>("learning_annotations_query", { targets }) : Promise.resolve([]);
export const getAnnotation = (id: string) => transport.call<Annotation | null>("learning_annotation_get", { id });
export const upsertAnnotation = (annotation: Annotation) => write<Annotation>("learning_annotation_upsert", { annotation });
export const deleteAnnotation = deletePdfAnnotation;
