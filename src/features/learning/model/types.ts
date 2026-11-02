/** Rectangles are fractions of the displayed PDF page, independent of zoom. */
export type PdfRect = { x: number; y: number; width: number; height: number };
export type PdfAnchor = { page: number; rects: PdfRect[] };

/**
 * A whole block of a rendered text (a table, a diagram, a code block, a
 * picture) or an area drawn on a PDF page: what kind, which of its kind it
 * was, and, for a link, the opening words of its rendered text.
 */
export type BlockRef = { kind: string; index: number; lead?: string };

/**
 * A passage of text found again by its words, so it survives small edits: the
 * quote with a little context either side, where it was last (only a hint),
 * the headings above it and, in a text file, its lines.
 */
export type TextAnchor = {
  exact: string; prefix: string; suffix: string;
  start: number; end: number;
  headings?: string[];
  lines?: [number, number];
  /** A whole block, whose Markdown source is `exact`. */
  block?: BlockRef;
};

type SourceBase = { id: string; title: string; quote: string };
export type LearningSource = SourceBase & (
  /** `commit`: the file was read at that commit (a pinned code lesson). */
  | { kind: "file"; path: string; lines?: [number, number]; commit?: string; anchor?: TextAnchor; annotationId?: string }
  | { kind: "pdf"; documentId: string; path: string; anchors: PdfAnchor[]; anchor?: TextAnchor; annotationId?: string }
  /** A passage of a document in an agent's library; `url` is where a source was published. */
  | { kind: "document"; agentId: string; documentId: string; url?: string; section?: string; anchor?: TextAnchor; annotationId?: string }
  | { kind: "web"; url: string }
  | { kind: "conversation"; sessionId: string; blockId: string }
);

export type ReadingDocument = { id: string; path: string; title: string; fingerprint: string; createdAt: number; updatedAt: number };
export type DiscussionRef = { sessionId: string; blockId: string };

/** What an annotation marks: a PDF, a document in an agent's library, or a text file. */
export type AnnotationTarget =
  | { kind: "pdf"; documentId: string }
  | { kind: "document"; agentId: string; documentId: string }
  | { kind: "file"; path: string };

/** A highlight, with an optional note, in any reader. PDF marks also keep page rectangles. */
export type Annotation = {
  id: string;
  /** The PDF's record, for a PDF mark; empty otherwise. */
  documentId: string;
  target: AnnotationTarget;
  anchor?: TextAnchor;
  source: LearningSource;
  anchors: PdfAnchor[];
  note: string;
  discussions: DiscussionRef[];
  createdAt: number;
  updatedAt: number;
};
/** The name PDF code has always used. */
export type PdfAnnotation = Annotation;

export type LearningMessageContext = { sources?: LearningSource[] };
