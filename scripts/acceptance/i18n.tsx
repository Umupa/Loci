// Synthetic browser preview: real UI components, no user data or running agents.
import { mockIPC, mockWindows } from "@tauri-apps/api/mocks";
import { createRoot } from "react-dom/client";
import { useState } from "react";
import { SettingsView } from "../../src/features/settings/ui/SettingsView";
import { SettingsNav } from "../../src/app/shell/SettingsRail";
import { AccessPicker } from "../../src/features/sessions/ui/AccessPicker";
import { EmptySession } from "../../src/features/sessions/ui/EmptySession";
import type { SettingsSectionId } from "../../src/features/settings/model/settings";
import type { RuntimeMode } from "../../src/features/sessions/model/session";
import "../../src/styles/index.css";

mockWindows("localization-preview");
mockIPC((command) => {
  if (command === "plugin:app|version") return "0.1.0";
  if (command === "provider_account_identity") return null;
  if (command === "plugin:event|listen") return 1;
  if (command === "plugin:window|is_maximized") return false;
  return undefined;
});
document.documentElement.classList.add("dark");
function Preview() {
  const [section, setSection] = useState<SettingsSectionId>("general");
  const [mode, setMode] = useState<RuntimeMode>("supervised");
  const [draft, setDraft] = useState("");
  return <div className="flex h-screen bg-background-base text-content">
    <aside className="flex w-52 shrink-0 flex-col border-r border-stroke">
      <SettingsNav section={section} onSelect={setSection} onClose={() => {}}/>
    </aside>
    <SettingsView section={section} onSelectSection={setSection} cwd="/preview/中文项目" sessions={[]} besideRail onClose={() => {}} onOpenSession={() => {}} onArchiveSession={() => {}} onDeleteSession={() => {}}/>
    <aside className="flex w-80 flex-col border-l border-stroke">
      <EmptySession cwd="/preview/中文项目" composer={<div className="rounded-xl border border-stroke p-3">
        <textarea aria-label="Preview draft" className="w-full bg-transparent text-sm outline-none" placeholder="Ask, / for commands, @ for files, notes, drawings…" value={draft} onChange={(event) => setDraft(event.target.value)}/>
        <AccessPicker value={mode} onChange={setMode}/>
      </div>}/>
    </aside>
  </div>;
}
createRoot(document.getElementById("root")!).render(<Preview/>);
