import type { ReactNode } from "react";
import { SettingsLanguage } from "../../shared/i18n/SettingsLanguage";
import { t, useLocale } from "../../shared/i18n/locale";
import { ArrowLeft, type IconComponent } from "../../shared/ui/icons";
import { useLockOverscroll } from "../../shared/hooks/useLockOverscroll";
import { settingsSectionsByGroup, type SettingsSectionId, } from "../../features/settings/model/settings";
import { agentLook, type Agent } from "../../features/agents/model/agent";
import { AgentAvatar } from "../../features/agents/ui/AgentAvatar";
type Props = {
    section: SettingsSectionId;
    onSelect: (section: SettingsSectionId) => void;
    onClose: () => void;
    /** Each mentor is a page of its own, listed first under Mentors. */
    mentors?: readonly Agent[];
    /** The mentor whose page is open, in place of a section. */
    mentorId?: string | null;
    onSelectMentor?: (agentId: string) => void;
};
/** Body of the project rail while settings are open. */
export function SettingsNav(props: Props) {
    return <SettingsLanguage><SettingsNavContent {...props}/></SettingsLanguage>;
}
function SettingsNavContent({ section, onSelect, onClose, mentors = [], mentorId = null, onSelectMentor }: Props) {
  useLocale();
    const lockOverscroll = useLockOverscroll<HTMLDivElement>();
    return (<>
      <div ref={lockOverscroll} aria-label={t("Settings")} className="flex min-h-0 flex-1 flex-col gap-5 overflow-y-auto overscroll-none px-2 py-3">
        {settingsSectionsByGroup().map((group) => (<div key={group.id} className="flex flex-col gap-px">
            <div className="px-2 pb-1 text-[11px] font-medium text-content/40">
              {group.label}
            </div>
            {group.id === "agents" && onSelectMentor ? mentors.map((agent) => {
                const look = agentLook(agent);
                return <NavRow key={agent.id} label={look.name} active={agent.id === mentorId} onClick={() => onSelectMentor(agent.id)}
                  leading={<AgentAvatar name={look.avatar} color={look.color} className="size-4 shrink-0"/>}/>;
            }) : null}
            {group.sections.map((item) => (<NavRow key={item.id} label={item.label} active={!mentorId && item.id === section} onClick={() => onSelect(item.id)}/>))}
          </div>))}
      </div>
      <div className="flex shrink-0 flex-col gap-px p-2">
        <NavRow label={t("Back")} icon={ArrowLeft} onClick={onClose}/>
      </div>
    </>);
}
function NavRow({ label, icon: Icon, leading, active = false, onClick, }: {
    label: string;
    icon?: IconComponent;
    /** In place of the icon, such as a mentor's face. */
    leading?: ReactNode;
    active?: boolean;
    onClick: () => void;
}) {
  useLocale();
    return (<button type="button" onClick={onClick} aria-current={active ? "true" : undefined} className={`flex h-8 w-full items-center gap-2 rounded-md px-2 text-left ${active
            ? "bg-selection text-content"
            : "text-content/60 hover:bg-content/5 hover:text-content"}`}>
      {leading ?? (Icon ? <Icon className="size-4 shrink-0 opacity-70"/> : null)}
      <span className="min-w-0 flex-1 truncate text-[13px] leading-tight">
        {label}
      </span>
    </button>);
}
