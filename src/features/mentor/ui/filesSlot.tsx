import type { ComponentType } from "react";
import { AgentFilesSection } from "../../agents/ui/AgentFilesSection";

export type MentorFilesSectionProps = {
  agentId: string;
  /** Opens the file in the reader, in place of what it shows. */
  onOpenFile: (path: string) => void;
  onFileMoved?: (from: string, to: string) => void;
  onFileDeleted?: (path: string) => void;
  /** The library's filter, applied to every folder. */
  filter?: string;
  /** Clears that filter, as choosing a folder from its matches does. */
  onClearQuery?: () => void;
};

/** The mentor's working folder (and any other folders it was given) in the library. */
export const MentorFilesSection: ComponentType<MentorFilesSectionProps> | null = AgentFilesSection;
