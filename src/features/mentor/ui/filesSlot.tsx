import type { ComponentType } from "react";
import type { OpenFileFn } from "../../files/model/filePlace";

export type MentorFilesSectionProps = {
  agentId: string;
  onOpenFile: OpenFileFn;
  onFileMoved?: (from: string, to: string) => void;
  onFileDeleted?: (path: string) => void;
};

/**
 * The mentor's working folder in the library. The component is built
 * separately (`agents/ui/AgentFilesSection`); until it lands the section
 * stays out of the library.
 */
export const MentorFilesSection: ComponentType<MentorFilesSectionProps> | null = null;
