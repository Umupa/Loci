import type { Agent } from "../../features/agents/model/agent";
import type { AgentTemplate } from "../../features/agents/templates";
import type { LibrarySegment } from "../../features/mentor/model/libraryCourse";
import type { MentorLesson, MentorPage } from "../../features/mentor/model/mentorPage";
import type { HarnessId, Session } from "../../features/sessions/model/session";
import type { SessionSubmission } from "../hooks/useSessionSubmission";

/**
 * What commands reach in the window: the same hooks and functions the UI
 * uses. `App.tsx` builds it once; commands never get a second copy of state.
 */
export type CommandContext = {
  /** The identifier this build runs under (`com.loci.desktop` is the installed app). */
  identifier(): Promise<string>;
  /** Every mentor, in rail order. */
  agents(): readonly Agent[];
  activeAgentId(): string | null;
  /** Adds a mentor, from a template or blank, without switching to it. */
  createAgent(template?: AgentTemplate): Promise<string>;
  /** Removes a mentor as the rail does; `confirmed` skips the dialog. False when the user declined. */
  removeAgent(id: string, confirmed: boolean): Promise<boolean>;
  /** Clears a mentor's conversation; `confirmed` skips the dialog. False when the user declined. */
  resetAgent(id: string, confirmed: boolean): Promise<boolean>;
  /** Shows a mentor in the window, as choosing it on the rail does. */
  switchAgent(id: string): Promise<boolean>;
  /** The mentor's conversation, loaded and kept in memory as opening it would. */
  agentChat(id: string): Promise<Session>;
  /**
   * Reads these providers' model catalogs now, as opening the model picker
   * does, waiting only a few seconds for slow CLIs.
   */
  refreshModels(harnesses: readonly HarnessId[]): Promise<void>;
  /** A session the window holds in memory. */
  liveSession(id: string): Session | undefined;
  submission: Pick<SessionSubmission, "submit" | "stopSessionWork" | "changeModel" | "changeModelSettings" | "changeRuntimeMode">;
  flushPersistence(): Promise<void>;
  reader: {
    /** Replaces what the mentor's reader shows; `focus` also brings the mentor on screen. */
    show(agentId: string, page: MentorPage, focus: boolean): Promise<void>;
    close(agentId: string): Promise<boolean>;
    current(agentId: string): { page?: MentorPage; lesson?: MentorLesson };
  };
  library: {
    /** Chooses the library's segment, its course or its filter, and shows the library. */
    open(agentId: string, change: { segment?: LibrarySegment; course?: string; filter?: string }): void;
    current(agentId: string): { visible: boolean; segment?: LibrarySegment; course?: string; filter?: { segment: LibrarySegment; text: string } };
  };
  /** Runs one of the app CLI's agent actions as the given session would. */
  agentApp(source: Session, requestId: string, action: string, input: Record<string, unknown>): Promise<unknown>;
};
