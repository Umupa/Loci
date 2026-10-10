export type JsonValue = null | boolean | number | string | JsonValue[] | { [key: string]: JsonValue };

/** Rectangles are fractions of the displayed PDF page, independent of zoom. */
export type PdfRect = { x: number; y: number; width: number; height: number };
export type PdfAnchor = { page: number; rects: PdfRect[] };

type SourceBase = { id: string; title: string; quote: string };
export type LearningSource = SourceBase & (
  | { kind: "file"; path: string; lines?: [number, number] }
  | { kind: "pdf"; documentId: string; path: string; anchors: PdfAnchor[]; annotationId?: string }
  | { kind: "web"; url: string }
  | { kind: "conversation"; sessionId: string; blockId: string }
);

export type ReadingDocument = { id: string; path: string; title: string; fingerprint: string; createdAt: number; updatedAt: number };
export type DiscussionRef = { sessionId: string; blockId: string };
export type PdfAnnotation = {
  id: string;
  documentId: string;
  source: LearningSource;
  anchors: PdfAnchor[];
  note: string;
  discussions: DiscussionRef[];
  createdAt: number;
  updatedAt: number;
};

export type WidgetOwner = { kind: "agent" | "session"; id: string };
export type WidgetRef = { owner: WidgetOwner; id: string };
export type WidgetSpec = { id: string; title: string; subject?: string; html: string; sourceIds: string[] };
export type StoredWidget = WidgetSpec & {
  owner: WidgetOwner;
  sourceSessionId: string;
  sourceBlockId: string;
  revision: number;
  saved: boolean;
  state: JsonValue;
  createdAt: number;
  updatedAt: number;
};
export type WidgetContext = WidgetRef & {
  title: string;
  revision: number;
  state: JsonValue;
  selection?: string;
  html?: string;
};
export type LearningMessageContext = { sources?: LearningSource[]; widgetContext?: WidgetContext };
