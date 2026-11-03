import { IS_MAC } from "../../../platform/tauri/platform";
import { t, useLocale } from "../../../shared/i18n/locale";
import { ReadOnly } from "../../../shared/ui/ReadOnly";
import { WindowControls } from "../../../app/shell/WindowControls";
import type { RecentProject } from "../../projects/model/recents";
import type { HarnessId, RuntimeMode, Session } from "../../sessions/model/session";
import { agentLook, type Agent } from "../model/agent";
import { markAgentAccessMigrated } from "../model/agentAccess";
import { AgentDetails } from "./AgentDetails";

type Props = {
  agent: Agent;
  /** Its conversation; absent until it has loaded. */
  session?: Session;
  recents: readonly RecentProject[];
  onModelChange: (sessionId: string, harness: HarnessId, model: string) => void;
  onModelSettingsChange: (sessionId: string, settings: Record<string, string>) => void;
  onRuntimeModeChange: (sessionId: string, mode: RuntimeMode) => void;
  onPickFolders: () => Promise<string[]>;
  onReset: () => void;
  onDelete: () => void;
  readOnly?: boolean;
  /** Beside the mentor rail, where the window's buttons are not. */
  besideRail?: boolean;
};

/**
 * A mentor's settings as a page of the Settings window, chosen in its left
 * column like any other section. Nothing is laid over the workspace.
 */
export function MentorSettingsPage({ agent, session, recents, onModelChange, onModelSettingsChange, onRuntimeModeChange, onPickFolders, onReset, onDelete, readOnly = false, besideRail = true }: Props) {
  useLocale();
  const name = agentLook(agent).name;
  return <div role="region" aria-label={t("Settings")} data-app-settings data-mentor-settings={agent.id} className="flex min-h-0 min-w-0 flex-1 flex-col text-content">
    <div className="flex h-10 shrink-0 select-none items-center border-b border-stroke" data-tauri-drag-region="deep">
      {IS_MAC && !besideRail ? <div className="w-[78px] shrink-0" /> : null}
      <div className="flex min-w-0 flex-1 items-center gap-2 px-3 text-[13px]">
        <span className="shrink-0 text-content/45">{t("Settings")}</span>
        <span aria-hidden className="shrink-0 text-content/25">/</span>
        <span className="min-w-0 truncate text-content">{name}</span>
      </div>
      {IS_MAC ? null : <WindowControls />}
    </div>
    {session ? <ReadOnly readOnly={readOnly}><AgentDetails agent={agent} session={session} recents={recents} refreshKey={session.busy}
      onModelChange={(harness, model) => onModelChange(session.id, harness, model)}
      onModelSettingsChange={(settings) => onModelSettingsChange(session.id, settings)}
      onRuntimeModeChange={(mode) => {
        onRuntimeModeChange(session.id, mode);
        // Choosing here is the mentor's access from now on, migration included.
        markAgentAccessMigrated(agent.id);
      }}
      onPickFolders={onPickFolders} onReset={onReset} onDelete={onDelete} onClose={() => undefined} /></ReadOnly>
      : <p role="status" className="p-8 text-[13px] text-content/50">{t("Opening…")}</p>}
  </div>;
}
