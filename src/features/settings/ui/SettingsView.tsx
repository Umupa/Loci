import { ResetWorkspace } from "./ResetWorkspace";
import { SettingsLanguage } from "../../../shared/i18n/SettingsLanguage";
import { t, useLocale, getLocale, useLanguagePreference, setLanguagePreference, type LanguagePreference } from "../../../shared/i18n/locale";
import { getVersion } from "@tauri-apps/api/app";
import { shortcutPreview, shortcutFromKeyEvent } from "../../../shared/lib/shortcuts";
import { invoke } from "@tauri-apps/api/core";
import { ask } from "@tauri-apps/plugin-dialog";
import { Check, ChevronDown, ExternalLink, FolderOpen, Globe, ImagePlus, Loader, Pencil, Plus, RefreshCw, RotateCcw, Search, Trash2, X, } from "../../../shared/ui/icons";
import { createContext, useCallback, useContext, useEffect, useId, useMemo, useRef, useState, useSyncExternalStore, type FormEvent, type KeyboardEvent as ReactKeyboardEvent, type ReactNode, } from "react";
import { HarnessIcon } from "../../sessions/ui/HarnessIcon";
import { ColorPickerPopover, ColorSwatchRow, } from "../../../shared/ui/ColorPickerPopover";
import { Popover } from "../../../shared/ui/Popover";
import { SecondaryButton } from "../../../shared/ui/SecondaryButton";
import { agentLook, agentProjectsPhrase, agentsSnapshot, listAgents, subscribeAgents, type Agent } from "../../agents/model/agent";
import { defaultAgentName } from "../../agents/model/agentAvatars";
import { resetAgentDefaults } from "../../agents/model/agentFiles";
import { TEMPLATE_TEXT_FIELDS, agentTemplateEdited, agentTemplatesSnapshot, listAgentTemplates, resetAgentTemplate, saveAgentTemplate, subscribeAgentTemplates, type AgentTemplate, type TemplateTextField } from "../../agents/model/agentTemplates";
import { AgentAvatar } from "../../agents/ui/AgentAvatar";
import { GradientBlurBackground } from "./GradientBlurBackground";
import { McpSettings } from "./McpSettings";
import { RemoveProjectDialog } from "../../projects/ui/RemoveProjectDialog";
import { WindowControls } from "../../../app/shell/WindowControls";
import { useLockOverscroll } from "../../../shared/hooks/useLockOverscroll";
import { useColorScheme } from "../../../shared/hooks/useColorScheme";
import { applyChatBackground, applyChatBackgroundEmptyOpacity, applyChatBackgroundSessionOpacity, applyChatBackgroundScope, applyBodyGlass, applySidebarBlur, applySidebarOpacity, applyThemeDarkLightness, applyThemePreference, applyThemeTint, BODY_GLASS_DEFAULT, ACCENT_COLOR_DEFAULT, CHAT_BACKGROUND_EMPTY_OPACITY_DEFAULT, CHAT_BACKGROUND_OPACITY_MAX, CHAT_BACKGROUND_OPACITY_MIN, CHAT_BACKGROUND_SESSION_OPACITY_DEFAULT, CHAT_BACKGROUND_SCOPE_DEFAULT, THEME_PREFERENCE_DEFAULT, chatBackgroundSrc, loadBodyGlass, loadAccentColor, loadChatBackgroundEmptyOpacity, loadChatBackgroundPath, loadChatBackgroundSessionOpacity, loadChatBackgroundScope, loadNewThreadBackgroundEffect, loadThemeDarkLightness, loadThemePreference, loadSidebarBlur, loadSidebarOpacity, loadThemeHue, loadThemeSaturation, loadTranscriptLayout, loadTranscriptAnchor, saveBodyGlass, saveAccentColor, saveChatBackgroundEmptyOpacity, saveChatBackgroundPath, saveChatBackgroundSessionOpacity, saveChatBackgroundScope, setNewThreadBackgroundEffect, saveThemeDarkLightness, saveThemePreference, saveSidebarBlur, saveSidebarOpacity, saveThemeHue, saveThemeSaturation, isLightScheme, saveTranscriptLayout, saveTranscriptAnchor, syncNativeGlass, TRANSCRIPT_ANCHOR_CHANGE_EVENT, SIDEBAR_BLUR_DEFAULT, SIDEBAR_BLUR_MAX, SIDEBAR_BLUR_MIN, SIDEBAR_OPACITY_DEFAULT, SIDEBAR_OPACITY_MAX, SIDEBAR_OPACITY_MIN, THEME_DARK_LIGHTNESS_DEFAULT, THEME_DARK_LIGHTNESS_MAX, THEME_DARK_LIGHTNESS_MIN, THEME_HUE_DEFAULT, THEME_HUE_MAX, THEME_HUE_MIN, THEME_SATURATION_DEFAULT, THEME_SATURATION_MAX, THEME_SATURATION_MIN, type ThemePreference, type ChatBackgroundScope, NEW_THREAD_BACKGROUND_EFFECTS, NEW_THREAD_BACKGROUND_EFFECT_LABELS, NEW_THREAD_BACKGROUND_EFFECT_DESCRIPTIONS, NEW_THREAD_BACKGROUND_EFFECT_DEFAULT, type NewThreadBackgroundEffect, type TranscriptLayout, } from "../model/appearance";
import { pickAndSaveChatBackground, removeChatBackground, } from "../../projects/model/chatBackground";
import { applyEffectiveAccent, loadThemeId, saveThemeWallpaperAuto, setTheme, } from "../model/appearance";
import { applyFonts, loadCodeFont, loadUiFont, normalizeFontFamily, OMARCHY_FONTS, rendersMonospace, saveCodeFont, saveUiFont, subscribeFonts, UI_FONT_FOLLOWS_CODE, } from "../model/fonts";
import { findTheme, isThemeWallpaperPath, resolveTheme, type ThemeWallpaper, } from "../model/themes";
import { ThemeGallery, WallpaperStrip } from "./ThemeGallery";
import { applyUiScale, loadUiScale, saveUiScale, subscribeUiScale, UI_SCALE_DEFAULT, UI_SCALE_PERCENTS, } from "../model/uiScale";
import { getHarnessAvailabilitySnapshot, harnessUnavailableHint, isHarnessAvailable, probeHarnessAvailability, subscribeHarnessAvailability, } from "../../../integrations/harness/core/availability";
import { inspectHarnessBinary, type HarnessBinaryInspection, } from "../../../integrations/harness/core/child";
import { loadProviderBinaryPath, providerBinaryPathChangePending, saveProviderBinaryPath, type ConfigurableBinaryProvider, } from "../../providers/model/providerBinaryPaths";
import { refreshHarnessCatalogs } from "../../../integrations/harness/core/registry";
import { loginHarness } from "../../../integrations/harness/core/auth";
import { defaultModelId, firstEnabledHarness, getModelSnapshot, hasLiveCatalog, loadDefaultModels, loadHiddenPickerProviders, loadLastModelChoice, modelsFor, resolveModel, saveDefaultModel, saveLastModelChoice, savePickerProviderVisible, subscribeModels, } from "../../sessions/model/models";
import { pathKey, prettyCwd, projectKey, projectName, } from "../../../shared/lib/paths";
import { revealPath } from "../../../platform/tauri/fs";
import { IS_LINUX, IS_MAC, IS_WIN } from "../../../platform/tauri/platform";
import { loadArchivedProjects, looksLikeProject, subscribeArchivedProjects, type ArchivedProject, type RecentProject, } from "../../projects/model/recents";
import { HARNESSES, HARNESS_TITLE, sessionDisplayTitle, type HarnessId, } from "../../sessions/model/session";
import { loadProjectProviderSettings, projectProvidersRevision, setProjectDefaultModel, setProjectDefaultProvider, setProjectProviderHidden, subscribeProjectProviders, } from "../../sessions/model/projectProviders";
import { newProviderAccount, providerAccounts, PROVIDER_ACCOUNT_PROVIDERS, removeProviderAccount, renameProviderAccount, saveProviderAccount, subscribeProviderAccounts, type ProviderAccount, type ProviderAccountProvider, } from "../../providers/model/providerAccounts";
import { removeProviderAccountCredentials } from "../../providers/model/providerAccountCredentials";
import { identityKey, identityOrganizationTag, useProviderAccountIdentities, } from "../../providers/model/providerAccountIdentity";
import { ProviderAccountSubtitle } from "../../providers/ui/ProviderAccountSubtitle";
import { saveMaskEmails, saveShowRemainingUsage, useMaskEmails, useShowRemainingUsage, } from "../model/displayPrefs";
import { accountStatus, accountUsageKey, useProviderAccountUsage, } from "../../providers/model/accountUsage";
import { clearCachedRateLimits } from "../../providers/model/rateLimitsCache";
import { AccountStatusLabel, AccountUsageMeters, AccountUsageRefresh, } from "../../providers/ui/ProviderAccountUsage";
import { loadSessionSidebarFilters, saveSessionSidebarFilters, } from "../../sessions/model/sessionFilters";
import type { SessionSummary } from "../../sessions/data/sessionStore";
import { loadTabGroupColors, loadTabGroupCustomColors, loadTabGroupLabels, loadTabGroupMascots, resolveTabGroupColor, resolveTabGroupLabel, resolveTabGroupLogo, resolveTabGroupMascot, } from "../../workspace/model/tabGroups";
import { useTabGroupLogos } from "../../projects/hooks/useTabGroupLogos";
import { ProjectLogoIcon } from "../../projects/ui/ProjectLogoIcon";
import { ProjectMascot } from "../../projects/ui/ProjectMascot";
import { loadAgentsEnabled, saveAgentsEnabled, subscribeAgentsEnabled, filterKeybindings, currentKeybindings, loadClaudeHooks, loadComposerRunner, loadCloseToTray, loadCollapsedProjectRailMode, loadFollowUpBehavior, loadLiveAgentsEnabled, loadModelControls, loadNotesEnabled, loadKeybindingOverrides, loadTabAnimationsEnabled, loadTabLimit, saveTabLimit, TAB_LIMIT_CHOICES, saveClaudeHooks, saveComposerRunner, saveCloseToTray, saveCollapsedProjectRailMode, saveFollowUpBehavior, saveLiveAgentsEnabled, saveModelControls, saveNotesEnabled, saveKeybindingOverride, subscribeKeybindings, type KeybindingOverride, saveTabAnimationsEnabled, searchSettings, settingsSectionDescription, settingsSectionLabel, COLLAPSED_PROJECT_RAIL_MODE_DEFAULT, type CollapsedProjectRailMode, type FollowUpBehavior, type ModelControls, type SettingsSearchResult, type SettingsSectionId, } from "../model/settings";
import { loadSoundsEnabled, playCue, saveSoundsEnabled } from "../model/sounds";
import { cachedNotificationPermission, loadNotificationsEnabled, openNotificationSettings, probeNotificationPermission, requestNotificationPermission, saveNotificationsEnabled, type NotificationPermission, } from "../../notifications/model/notifications";
import { SkillsPage } from "../../skills/ui/SkillsPage";
import { ProjectNotificationSettings } from "../../notifications/ui/ProjectNotificationSettings";
import type {} from "../../sessions/model/session";
/**
 * The `data-setting-id` Settings should reveal when it opens: one of the ids in
 * `SETTINGS_INDEX`.
 */
export type SettingsAnchor = string;
const settingDomId = (id: string) => `setting-${id}`;
/** The row or group Settings just jumped to, so it can flash where you landed. */
const RevealedSetting = createContext<string | null>(null);
type Props = {
    section: SettingsSectionId;
    /** Card to scroll to; the General page is too long to land at the top. */
    anchor?: SettingsAnchor | null;
    /** Project to focus when opening notification settings from a quick action. */
    notificationProjectPath?: string | null;
    /** Changes for each quick action, including repeated requests for one project. */
    notificationSettingsRequest?: number;
    recents?: RecentProject[];
    cwd: string;
    sessions: SessionSummary[];
    besideRail?: boolean;
    onClose: () => void;
    /** Lets search jump to a setting that lives on another page. */
    onSelectSection?: (section: SettingsSectionId) => void;
    onOpenSession: (sessionId: string) => void;
    onArchiveSession: (sessionId: string, archived: boolean) => void;
    onDeleteSession: (sessionId: string) => void;
    onRestoreProject?: (path: string) => void;
    onDeleteProject?: (path: string) => void;
    collapsedProjectRailMode?: CollapsedProjectRailMode;
    onCollapsedProjectRailModeChange?: (mode: CollapsedProjectRailMode) => void;
};
export function SettingsView(props: Props) {
    return <SettingsLanguage><SettingsViewContent {...props}/></SettingsLanguage>;
}
function SettingsViewContent({ section, anchor = null, notificationProjectPath = null, notificationSettingsRequest = 0, recents, cwd, sessions, besideRail = false, onClose, onSelectSection, onOpenSession, onArchiveSession, onDeleteSession, onRestoreProject, onDeleteProject, collapsedProjectRailMode, onCollapsedProjectRailModeChange, }: Props) {
  useLocale();
    const lockOverscroll = useLockOverscroll<HTMLDivElement>();
    const [revealed, setRevealed] = useState<string | null>(anchor);
    const onCloseRef = useRef(onClose);
    onCloseRef.current = onClose;
    const appearance = useAppearanceSettings(collapsedProjectRailMode, onCollapsedProjectRailModeChange);
    useEffect(() => setRevealed(anchor), [anchor, notificationSettingsRequest]);
    // Section is a dependency so a search result on another page scrolls once
    // that page has mounted the row.
    useEffect(() => {
        if (!revealed)
            return;
        // A project quick action lets the project card focus itself after discovery.
        if (!(revealed === "project-notifications" && notificationProjectPath)) {
            document
                .getElementById(settingDomId(revealed))
                ?.scrollIntoView?.({ block: "center" });
        }
        const timer = window.setTimeout(() => setRevealed(null), 1800);
        return () => window.clearTimeout(timer);
    }, [revealed, section, notificationProjectPath, notificationSettingsRequest]);
    const onReveal = useCallback((next: SettingsSectionId, settingId: string | null) => {
        if (next !== section)
            onSelectSection?.(next);
        setRevealed(settingId);
    }, [onSelectSection, section]);
    useEffect(() => {
        const onKey = (event: KeyboardEvent) => {
            if (event.key !== "Escape" || event.defaultPrevented)
                return;
            event.preventDefault();
            event.stopPropagation();
            onCloseRef.current();
        };
        // Let dialogs and other Settings controls handle Escape first.
        window.addEventListener("keydown", onKey);
        return () => window.removeEventListener("keydown", onKey);
    }, []);
    return (<div role="region" aria-label={t("Settings")} data-app-settings className="flex min-h-0 min-w-0 flex-1 flex-col text-content">
      <div className="flex h-10 shrink-0 select-none items-center border-b border-stroke" data-tauri-drag-region="deep">
        {IS_MAC && !besideRail ? <div className="w-[78px] shrink-0"/> : null}
        <div className="flex min-w-0 flex-1 items-center gap-2 px-3 text-[13px]">
          <span className="shrink-0 text-content/45">{t("Settings")}</span>
          <span aria-hidden className="shrink-0 text-content/25">
            /
          </span>
          <span className="min-w-0 truncate text-content">
            {settingsSectionLabel(section)}
          </span>
        </div>
        <div className="flex shrink-0 items-center gap-1.5 pr-2" data-tauri-drag-region="false">
          {section === "appearance" ? (<button type="button" onClick={appearance.restoreDefaults} className="flex shrink-0 items-center gap-1.5 rounded-md px-2 py-1 text-[12px] text-content/50 hover:bg-content/10 hover:text-content">
              <RotateCcw className="size-3.5" strokeWidth={1.75}/>
              {t("Restore defaults")}</button>) : null}
          <SettingsSearch onReveal={onReveal}/>
        </div>
        {IS_MAC ? null : <WindowControls />}
      </div>

      {section === "skills" ? (<SkillsPage key={cwd} cwd={cwd} header={<PageHeader title={settingsSectionLabel(section)} description={settingsSectionDescription(section)}/>}/>) : (<RevealedSetting.Provider value={revealed}>
          <div ref={lockOverscroll} className="@container/settings min-h-0 flex-1 overflow-y-auto overscroll-none">
            <div className="mx-auto w-full max-w-5xl px-5 py-6 pb-16 @min-[560px]/settings:px-8 @min-[560px]/settings:py-8">
              <PageHeader title={settingsSectionLabel(section)} description={settingsSectionDescription(section)}/>
              {section === "general" ? (<><GeneralPage /><div id={settingDomId("project-notifications")} data-setting-id="project-notifications"><ProjectNotificationSettings cwd={cwd} recents={recents} notificationProjectPath={notificationProjectPath} notificationSettingsRequest={notificationSettingsRequest} highlighted={revealed === "project-notifications"} /></div></>) : null}

              {section === "appearance" ? (<AppearancePage appearance={appearance}/>) : null}
              {section === "agents" ? <AgentsPage /> : null}
              {section === "chat" ? <ChatPage /> : null}
              {section === "keybindings" ? <KeybindingsPage /> : null}
              {section === "mcp" ? (<McpSettings cwd={cwd} recents={recents}/>) : null}
              {section === "providers" ? (<ProvidersPage cwd={cwd} recents={recents}/>) : null}


              {section === "archive" ? (<ArchivePage cwd={cwd} sessions={sessions} onOpenSession={onOpenSession} onArchiveSession={onArchiveSession} onDeleteSession={onDeleteSession} onRestoreProject={onRestoreProject} onDeleteProject={onDeleteProject}/>) : null}
            </div>
          </div>
        </RevealedSetting.Provider>)}
    </div>);
}
/** Jumps to any setting by name, including ones on another page. */
function SettingsSearch({ onReveal, }: {
    onReveal: (section: SettingsSectionId, settingId: string | null) => void;
}) {
  useLocale();
    const [query, setQuery] = useState("");
    const [active, setActive] = useState(0);
    const root = useRef<HTMLDivElement>(null);
    const input = useRef<HTMLInputElement>(null);
    const listId = useId();
    const results = useMemo(() => searchSettings(query), [getLocale(), query]);
    const open = query.trim().length > 0;
    useEffect(() => setActive(0), [query]);
    const go = (result: SettingsSearchResult | undefined) => {
        if (!result)
            return;
        onReveal(result.section, result.settingId);
        setQuery("");
        input.current?.blur();
    };
    const onKeyDown = (event: ReactKeyboardEvent<HTMLInputElement>) => {
        if (event.key === "ArrowDown") {
            event.preventDefault();
            setActive((index) => Math.min(results.length - 1, index + 1));
            return;
        }
        if (event.key === "ArrowUp") {
            event.preventDefault();
            setActive((index) => Math.max(0, index - 1));
            return;
        }
        if (event.key === "Enter") {
            event.preventDefault();
            go(results[active]);
        }
    };
    return (<div ref={root} className="relative shrink-0">
      <label className="flex h-7 w-48 items-center gap-2 rounded-md border border-content/10 px-2 text-content/45 focus-within:border-content/20">
        <Search className="size-3.5 shrink-0" strokeWidth={1.75}/>
        <input ref={input} role="combobox" value={query} onChange={(event) => setQuery(event.target.value)} onKeyDown={onKeyDown} placeholder={t("Search settings")} aria-label={t("Search settings")} aria-expanded={open} aria-controls={listId} spellCheck={false} autoComplete="off" className="min-w-0 flex-1 bg-transparent text-[12px] text-content outline-none placeholder:text-content/35"/>
        {query ? (<button type="button" aria-label={t("Clear settings search")} onMouseDown={(event) => event.preventDefault()} onClick={() => {
                setQuery("");
                input.current?.focus();
            }} className="grid size-4 shrink-0 place-items-center rounded text-content/45 hover:text-content">
            <X className="size-3" strokeWidth={2}/>
          </button>) : null}
      </label>
      {open ? (<Popover anchor={root} side="bottom" align="end" width={300} maxHeight={320} onDismiss={(reason) => {
                setQuery("");
                if (reason === "escape")
                    input.current?.focus();
            }} id={listId} role="listbox" aria-label={t("Settings search results")} className="overflow-y-auto overscroll-contain p-1">
          {results.length === 0 ? (<p className="px-2 py-1.5 text-[12px] text-content/45">
              {t("No matching settings")}</p>) : (results.map((result, index) => (<button key={`${result.section}:${result.settingId ?? "*"}`} type="button" role="option" aria-selected={index === active} onMouseDown={(event) => event.preventDefault()} onMouseEnter={() => setActive(index)} onClick={() => go(result)} className={`flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-[12px] ${index === active
                    ? "bg-selection text-content"
                    : "text-content hover:bg-content/5"}`}>
                <span className="min-w-0 flex-1 truncate">{result.label}</span>
                <span className="shrink-0 text-[11px] text-content/40">
                  {result.settingId ? result.sectionLabel : t("Page")}
                </span>
              </button>)))}
        </Popover>) : null}
    </div>);
}
function GeneralPage({}: {}) {
  useLocale();
    const language = useLanguagePreference();
    const [soundsEnabled, setSoundsEnabled] = useState(loadSoundsEnabled);
    const [notificationsEnabled, setNotificationsEnabled] = useState(loadNotificationsEnabled);
    const [notificationPermission, setNotificationPermission] = useState<NotificationPermission>(cachedNotificationPermission);
    const [notesEnabled, setNotesEnabled] = useState(loadNotesEnabled);
    const [liveAgentsEnabled, setLiveAgentsEnabled] = useState(loadLiveAgentsEnabled);
    const [tabAnimationsEnabled, setTabAnimationsEnabled] = useState(loadTabAnimationsEnabled);
    const [tabLimit, setTabLimit] = useState(loadTabLimit);
    const [closeToTray, setCloseToTray] = useState(loadCloseToTray);
    // The user may flip the switch in System Settings and come back: re-read
    // the OS state whenever the window regains focus while the toggle is on.
    useEffect(() => {
        if (!notificationsEnabled)
            return;
        const refresh = () => {
            void probeNotificationPermission().then(setNotificationPermission);
        };
        refresh();
        window.addEventListener("focus", refresh);
        return () => window.removeEventListener("focus", refresh);
    }, [notificationsEnabled]);
    const onSoundsEnabled = (next: boolean) => {
        saveSoundsEnabled(next);
        setSoundsEnabled(next);
    };
    const onNotificationsEnabled = (next: boolean) => {
        saveNotificationsEnabled(next);
        setNotificationsEnabled(next);
        if (!next)
            return;
        void requestNotificationPermission().then(setNotificationPermission);
    };
    const onNotesEnabled = (next: boolean) => {
        saveNotesEnabled(next);
        setNotesEnabled(next);
    };
    const onLiveAgentsEnabled = (next: boolean) => {
        saveLiveAgentsEnabled(next);
        setLiveAgentsEnabled(next);
    };
    const onTabLimit = (value: string) => {
        const next = Number(value);
        saveTabLimit(next);
        setTabLimit(next);
    };
    const onTabAnimationsEnabled = (next: boolean) => {
        saveTabAnimationsEnabled(next);
        setTabAnimationsEnabled(next);
    };
    const onCloseToTray = (next: boolean) => {
        saveCloseToTray(next);
        setCloseToTray(next);
    };
    return (<>
      <Group title={t("Language")}>
        <Row id="language" label={t("Settings language")} description={t("Choose the language for Settings. The workspace stays in English.")}>
          <Select label={t("Settings language")} value={language} onChange={(value) => setLanguagePreference(value as LanguagePreference)} options={[
            { value: "system", label: t("Follow system") },
            { value: "zh-CN", label: "简体中文" },
            { value: "en", label: "English" },
          ]}/>
        </Row>
      </Group>
      <Group title={t("Alerts")} description={t("How Loci reaches you while you are looking somewhere else.")}>
        <Row id="sounds" label={t("Sounds")} description={t("Short cues for finished turns. Choose project notification categories below. Switches and Copy on a finished turn also play.")}>
          <Toggle label={t("Sounds")} on={soundsEnabled} onChange={onSoundsEnabled}/>
        </Row>
        <Row id="notifications" label={t("Notifications")} description={t("Notify when a reminder is due, or when an agent finishes or needs input in another session or while Loci is in the background. Click the notification to open that session.")}>
          {notificationsEnabled && notificationPermission === "denied" ? (<NotificationsBlocked />) : null}
          {notificationsEnabled && notificationPermission === "unsupported" ? (<span className="text-[12px] text-content/45">
              {t("Not available on this platform")}</span>) : null}
          <Toggle label={t("Notifications")} on={notificationsEnabled} onChange={onNotificationsEnabled}/>
        </Row>
      </Group>

      <Group title={t("Workspace")} description={t("How project navigation and workspace tabs behave.")}>

        <Row id="tab-animations" label={t("Tab animations")} description={t("Animate tabs as they open and close. Turn this off for instant tab changes.")}>
          <Toggle label={t("Tab animations")} on={tabAnimationsEnabled} onChange={onTabAnimationsEnabled}/>
        </Row>
        <Row id="tab-limit" label={t("Tab limit")} description={t("When a project has more tabs open than this, idle ones are put away to keep the strip usable. Nothing is closed for good: find them under Parked in the tab switcher. Tabs that are working, waiting on you, pinned, or holding unsent text are never put away.")}>
          <Select label={t("Tab limit")} value={String(tabLimit)} onChange={onTabLimit} options={TAB_LIMIT_CHOICES.map((choice) => ({ value: String(choice), label: choice === 0 ? t("No limit") : t("{0} tabs", choice) }))}/>
        </Row>
        <Row id="notes" label={t("Notes")} description={t("A global markdown notebook on the project rail. Save a finished turn from the transcript, then mention it later with @note or add it to chat.")}>
          <Toggle label={t("Notes")} on={notesEnabled} onChange={onNotesEnabled}/>
        </Row>

        <Row id="working-agents" label={t("Working agents")} description={t("When two or more chats are in flight, a card on the project rail lists them so you can jump across projects. Finished turns stay until you open that session.")}>
          <Toggle label={t("Working agents")} on={liveAgentsEnabled} onChange={onLiveAgentsEnabled}/>
        </Row>
        {IS_WIN && (<Row id="close-to-tray" label={t("Close to tray")} description={t("Closing a window hides it to the system tray instead of quitting, so running agents keep going. Reopen from the tray icon, and quit for real from its menu. Turn this off to have close end the window.")}>
            <Toggle label={t("Close to tray")} on={closeToTray} onChange={onCloseToTray}/>
          </Row>)}
      </Group>

      <Group title={t("About")}>
        <VersionRow />
      </Group>
      <Group title={t("Reset workspace")}>
        <ResetWorkspace />
      </Group>
    </>);
}
function ChatPage() {
  useLocale();
    const [composerRunner, setComposerRunner] = useState(loadComposerRunner);
    const [transcriptLayout, setTranscriptLayout] = useState<TranscriptLayout>(loadTranscriptLayout);
    const [transcriptAnchor, setTranscriptAnchor] = useState(loadTranscriptAnchor);
    const [followUpBehavior, setFollowUpBehavior] = useState<FollowUpBehavior>(loadFollowUpBehavior);
    const [modelControls, setModelControls] = useState<ModelControls>(loadModelControls);
    useEffect(() => {
        const onAnchor = (event: Event) => {
            setTranscriptAnchor((event as CustomEvent<boolean>).detail === true);
        };
        window.addEventListener(TRANSCRIPT_ANCHOR_CHANGE_EVENT, onAnchor);
        return () => {
            window.removeEventListener(TRANSCRIPT_ANCHOR_CHANGE_EVENT, onAnchor);
        };
    }, []);
    const onTranscriptLayout = (next: TranscriptLayout) => {
        saveTranscriptLayout(next);
        setTranscriptLayout(next);
    };
    const onTranscriptAnchor = (next: boolean) => {
        saveTranscriptAnchor(next);
        setTranscriptAnchor(next);
    };
    const onFollowUpBehavior = (next: FollowUpBehavior) => {
        saveFollowUpBehavior(next);
        setFollowUpBehavior(next);
    };
    const onModelControls = (next: ModelControls) => {
        saveModelControls(next);
        setModelControls(next);
    };
    return (<>
      <Group title={t("Transcript")} description={t("How a conversation reads as it grows.")}>
        <Row id="transcript-layout" label={t("Transcript layout")} description={t("Full width keeps user prompts as a spanning card. Chat aligns them to the right with a max width, like a messaging app.")}>
          <Segmented label={t("Transcript layout")} value={transcriptLayout} options={[
            { value: "full", label: t("Full width") },
            { value: "chat", label: t("Chat") },
        ]} onChange={onTranscriptLayout}/>
        </Row>
        <Row id="anchor-prompts" label={t("Anchor prompts to top")} description={t("When you send, the new prompt sits at the top of the transcript and the reply grows into the space below. Turn this off to keep the classic layout, with the latest message resting on the composer.")}>
          <Toggle label={t("Anchor prompts to top")} on={transcriptAnchor} onChange={onTranscriptAnchor}/>
        </Row>
      </Group>

      <Group title={t("Composer")} description={t("What the composer does with what you type.")}>
        <Row id="follow-up" label={t("Follow-up behavior")} description={t("Queue follow-ups until the active turn finishes, or steer the active turn immediately.")}>
          <Segmented label={t("Follow-up behavior")} value={followUpBehavior} options={[
            { value: "queue", label: t("Queue") },
            { value: "steer", label: t("Steer") },
        ]} onChange={onFollowUpBehavior}/>
        </Row>
        <Row id="composer-mascot" label={t("Composer mascot")} description={t("While an agent is working, the project mascot runs along the composer, jumps obstacles and occasionally collects a coin.")}>
          <Toggle label={t("Composer mascot")} on={composerRunner} onChange={(next) => { saveComposerRunner(next); setComposerRunner(next); }}/>
        </Row>
        <Row id="model-controls" label={t("Model controls")} description={t("Show model options beside the picker instead of inside the model menu.")}>
          <Segmented label={t("Model controls")} value={modelControls} options={[
            { value: "menu", label: t("Menu") },
            { value: "beside", label: t("Beside") },
        ]} onChange={onModelControls}/>
        </Row>
      </Group>






    </>);
}
type AppearanceSettings = ReturnType<typeof useAppearanceSettings>;
function useAppearanceSettings(controlledCollapsedProjectRailMode?: CollapsedProjectRailMode, onControlledCollapsedProjectRailModeChange?: (mode: CollapsedProjectRailMode) => void) {
  useLocale();
    const [themePreference, setThemePreference] = useState<ThemePreference>(loadThemePreference);
    const [themeId, setThemeId] = useState(loadThemeId);
    const [accentColor, setAccentColor] = useState(loadAccentColor);
    const [codeFont, setCodeFont] = useState(loadCodeFont);
    const [uiFont, setUiFont] = useState(loadUiFont);
    const [opacity, setOpacity] = useState(loadSidebarOpacity);
    const [blur, setBlur] = useState(loadSidebarBlur);
    const [themeHue, setThemeHue] = useState(loadThemeHue);
    const [themeSaturation, setThemeSaturation] = useState(loadThemeSaturation);
    const [themeDarkLightness, setThemeDarkLightness] = useState(loadThemeDarkLightness);
    const [bodyGlass, setBodyGlass] = useState(loadBodyGlass);
    const [chatBackgroundPath, setChatBackgroundPath] = useState(loadChatBackgroundPath);
    const [chatBackgroundEmptyOpacity, setChatBackgroundEmptyOpacity] = useState(loadChatBackgroundEmptyOpacity);
    const [chatBackgroundSessionOpacity, setChatBackgroundSessionOpacity] = useState(loadChatBackgroundSessionOpacity);
    const [chatBackgroundScope, setChatBackgroundScope] = useState<ChatBackgroundScope>(loadChatBackgroundScope);
    const [newThreadBackgroundEffect, setBackgroundEffect] = useState<NewThreadBackgroundEffect>(loadNewThreadBackgroundEffect);
    const [chatBackgroundBusy, setChatBackgroundBusy] = useState(false);
    const [chatBackgroundError, setChatBackgroundError] = useState<string | null>(null);
    const [uiScale, setUiScale] = useState(loadUiScale);
    const [storedCollapsedProjectRailMode, setStoredCollapsedProjectRailMode] = useState<CollapsedProjectRailMode>(loadCollapsedProjectRailMode);
    const collapsedProjectRailMode = controlledCollapsedProjectRailMode ?? storedCollapsedProjectRailMode;
    useEffect(() => subscribeUiScale(() => setUiScale(loadUiScale())), []);
    useEffect(() => subscribeFonts(() => {
        setCodeFont(loadCodeFont());
        setUiFont(loadUiFont());
    }), []);
    const onThemePreference = useCallback((next: ThemePreference) => {
        applyThemePreference(next);
        saveThemePreference(next);
        setThemePreference(next);
    }, []);
    const onAccentColor = useCallback((value: string | null) => {
        saveAccentColor(value);
        // The theme's accent shows through while none is picked.
        applyEffectiveAccent();
        setAccentColor(loadAccentColor());
    }, []);
    const onTheme = useCallback((id: string | null) => {
        setTheme(id);
        setThemeId(loadThemeId());
        // Picking a theme may also have moved the chat background to its wallpaper.
        setChatBackgroundPath(loadChatBackgroundPath());
    }, []);
    const onSelectThemeWallpaper = useCallback((wallpaper: ThemeWallpaper) => {
        saveChatBackgroundPath(wallpaper.path);
        applyChatBackground(wallpaper.path);
        saveThemeWallpaperAuto(true);
        setChatBackgroundPath(wallpaper.path);
        setChatBackgroundError(null);
    }, []);
    const onCodeFont = useCallback((value: string | null) => {
        saveCodeFont(value);
        applyFonts();
        setCodeFont(loadCodeFont());
    }, []);
    const onUiFont = useCallback((value: string | null) => {
        saveUiFont(value);
        applyFonts();
        setUiFont(loadUiFont());
    }, []);
    const onOpacity = useCallback((percent: number) => {
        const next = applySidebarOpacity(percent / 100);
        saveSidebarOpacity(next);
        setOpacity(next);
    }, []);
    const onBlur = useCallback((radius: number) => {
        const next = applySidebarBlur(radius);
        saveSidebarBlur(next);
        setBlur(next);
    }, []);
    const onTint = useCallback((hue: number, saturation: number) => {
        const next = applyThemeTint(hue, saturation);
        saveThemeHue(next.hue);
        saveThemeSaturation(next.saturation);
        setThemeHue(next.hue);
        setThemeSaturation(next.saturation);
    }, []);
    const onDarkLightness = useCallback((value: number) => {
        const next = applyThemeDarkLightness(value);
        saveThemeDarkLightness(next);
        setThemeDarkLightness(next);
    }, []);
    const onBodyGlass = useCallback((next: boolean) => {
        applyBodyGlass(next);
        saveBodyGlass(next);
        setBodyGlass(next);
        if (IS_LINUX)
            syncNativeGlass(isLightScheme() ? "light" : "dark");
    }, []);
    const onChooseChatBackground = useCallback(async () => {
        setChatBackgroundBusy(true);
        setChatBackgroundError(null);
        try {
            const path = await pickAndSaveChatBackground(t("Choose chat background"));
            if (!path)
                return;
            saveChatBackgroundPath(path);
            applyChatBackground(path);
            saveThemeWallpaperAuto(true);
            setChatBackgroundPath(path);
        }
        catch (error) {
            setChatBackgroundError(error instanceof Error ? error.message : String(error));
        }
        finally {
            setChatBackgroundBusy(false);
        }
    }, []);
    const onClearChatBackground = useCallback(async () => {
        setChatBackgroundBusy(true);
        setChatBackgroundError(null);
        try {
            await removeChatBackground();
            // Removing a theme's wallpaper means: stop bringing it back with the theme.
            if (isThemeWallpaperPath(loadChatBackgroundPath()))
                saveThemeWallpaperAuto(false);
            saveChatBackgroundPath(null);
            applyChatBackground(null);
            setChatBackgroundPath(null);
        }
        catch (error) {
            setChatBackgroundError(error instanceof Error ? error.message : String(error));
        }
        finally {
            setChatBackgroundBusy(false);
        }
    }, []);
    const onChatBackgroundEmptyOpacity = useCallback((percent: number) => {
        const next = applyChatBackgroundEmptyOpacity(percent / 100);
        saveChatBackgroundEmptyOpacity(next);
        setChatBackgroundEmptyOpacity(next);
    }, []);
    const onChatBackgroundSessionOpacity = useCallback((percent: number) => {
        const next = applyChatBackgroundSessionOpacity(percent / 100);
        saveChatBackgroundSessionOpacity(next);
        setChatBackgroundSessionOpacity(next);
    }, []);
    const onChatBackgroundScope = useCallback((next: ChatBackgroundScope) => {
        applyChatBackgroundScope(next);
        saveChatBackgroundScope(next);
        setChatBackgroundScope(next);
    }, []);
    const onNewThreadBackgroundEffect = useCallback((next: NewThreadBackgroundEffect) => {
        setNewThreadBackgroundEffect(next);
        setBackgroundEffect(next);
    }, []);
    const onUiScale = useCallback((percent: number) => {
        const next = saveUiScale(percent / 100);
        setUiScale(next);
        void applyUiScale(next);
    }, []);
    const onCollapsedProjectRailMode = useCallback((next: CollapsedProjectRailMode) => {
        saveCollapsedProjectRailMode(next);
        setStoredCollapsedProjectRailMode(next);
        onControlledCollapsedProjectRailModeChange?.(next);
    }, [onControlledCollapsedProjectRailModeChange]);
    const restoreDefaults = useCallback(() => {
        onTheme(null);
        saveThemeWallpaperAuto(true);
        onCodeFont(null);
        onUiFont(null);
        onThemePreference(THEME_PREFERENCE_DEFAULT);
        onAccentColor(ACCENT_COLOR_DEFAULT);
        onOpacity(Math.round(SIDEBAR_OPACITY_DEFAULT * 100));
        onBlur(SIDEBAR_BLUR_DEFAULT);
        onTint(THEME_HUE_DEFAULT, THEME_SATURATION_DEFAULT);
        onDarkLightness(THEME_DARK_LIGHTNESS_DEFAULT);
        onBodyGlass(BODY_GLASS_DEFAULT);
        onChatBackgroundEmptyOpacity(Math.round(CHAT_BACKGROUND_EMPTY_OPACITY_DEFAULT * 100));
        onChatBackgroundSessionOpacity(Math.round(CHAT_BACKGROUND_SESSION_OPACITY_DEFAULT * 100));
        onChatBackgroundScope(CHAT_BACKGROUND_SCOPE_DEFAULT);
        onNewThreadBackgroundEffect(NEW_THREAD_BACKGROUND_EFFECT_DEFAULT);
        if (chatBackgroundPath)
            void onClearChatBackground();
        onUiScale(Math.round(UI_SCALE_DEFAULT * 100));
        onCollapsedProjectRailMode(COLLAPSED_PROJECT_RAIL_MODE_DEFAULT);
    }, [
        chatBackgroundPath,
        onBlur,
        onBodyGlass,
        onChatBackgroundEmptyOpacity,
        onChatBackgroundSessionOpacity,
        onChatBackgroundScope,
        onNewThreadBackgroundEffect,
        onClearChatBackground,
        onAccentColor,
        onTheme,
        onCodeFont,
        onUiFont,
        onThemePreference,
        onOpacity,
        onTint,
        onDarkLightness,
        onUiScale,
        onCollapsedProjectRailMode,
    ]);
    return {
        themePreference,
        themeId,
        accentColor,
        codeFont,
        uiFont,
        opacity,
        blur,
        themeHue,
        themeSaturation,
        themeDarkLightness,
        bodyGlass,
        chatBackgroundPath,
        chatBackgroundEmptyOpacity,
        chatBackgroundSessionOpacity,
        chatBackgroundScope,
        newThreadBackgroundEffect,
        chatBackgroundBusy,
        chatBackgroundError,
        uiScale,
        collapsedProjectRailMode,
        onThemePreference,
        onTheme,
        onAccentColor,
        onCodeFont,
        onUiFont,
        onSelectThemeWallpaper,
        onOpacity,
        onBlur,
        onTint,
        onDarkLightness,
        onBodyGlass,
        onChooseChatBackground,
        onClearChatBackground,
        onChatBackgroundEmptyOpacity,
        onChatBackgroundSessionOpacity,
        onChatBackgroundScope,
        onNewThreadBackgroundEffect,
        onUiScale,
        onCollapsedProjectRailMode,
        restoreDefaults,
    };
}
function AppearancePage({ appearance }: {
    appearance: AppearanceSettings;
}) {
  useLocale();
    const percent = Math.round(appearance.opacity * 100);
    const glassDisabled = useColorScheme() === "light";
    const theme = findTheme(appearance.themeId);
    return (<>
      <Group title={t("Theme")} description={theme
            ? t("{0} sets the colors, the code colors and whether Loci is dark or light.", theme.name)
            : t("Dark and light share the same tint, so the color settings below apply to both.")}>
        <BlockRow id="color-theme" label={t("Color theme")} description={t("Palettes and wallpapers from Omarchy's themes. Default keeps Loci's own colors, which the controls below adjust.")}>
          <ThemeGallery activeId={appearance.themeId} onSelect={appearance.onTheme}/>
        </BlockRow>
        <Row id="theme" label={t("Mode")} description={theme ? t("Set by the {0} theme.", theme.name) : t("System follows the OS appearance.")}>
          <Segmented label={t("Mode")} value={theme ? theme.mode : appearance.themePreference} disabled={theme != null} options={[
            { value: "system", label: t("System") },
            { value: "dark", label: t("Dark") },
            { value: "light", label: t("Light") },
        ]} onChange={appearance.onThemePreference}/>
        </Row>
        <Row id="accent-color" label={t("Accent color")} description={theme
            ? t("Used for the composer send button and your message bubbles. The theme picks one unless you do.")
            : t("Used for the composer send button and your message bubbles.")}>
          <AccentColorPicker value={appearance.accentColor} themeAccent={theme ? resolveTheme(theme).accent : null} onChange={appearance.onAccentColor}/>
        </Row>

      </Group>

      <Group title={t("Color")} description={theme
            ? t("The {0} theme sets these colors. Choose Default above to adjust them.", theme.name)
            : t("Hue and saturation tint every surface. Lightness only moves the dark theme.")}>
        <Row id="hue" label={t("Hue")} description={t("Base hue for accents and tinted surfaces.")}>
          <Slider label={t("Hue")} value={appearance.themeHue} display={`${appearance.themeHue}°`} min={THEME_HUE_MIN} max={THEME_HUE_MAX} onChange={(value) => appearance.onTint(value, appearance.themeSaturation)} disabled={theme != null}/>
        </Row>
        <Row id="saturation" label={t("Saturation")} description={t("How strongly the hue tints the interface. Zero keeps it neutral.")}>
          <Slider label={t("Saturation")} value={appearance.themeSaturation} display={`${appearance.themeSaturation}%`} min={THEME_SATURATION_MIN} max={THEME_SATURATION_MAX} onChange={(value) => appearance.onTint(appearance.themeHue, value)} disabled={theme != null}/>
        </Row>
        <Row id="dark-lightness" label={t("Dark-mode lightness")} description={glassDisabled
            ? t("This only affects dark mode. Your dark-mode value is preserved.")
            : t("Base brightness of the dark theme. Lower values are darker; zero is true black.")}>
          <Slider label={t("Dark-mode lightness")} value={appearance.themeDarkLightness} display={`${appearance.themeDarkLightness}%`} min={THEME_DARK_LIGHTNESS_MIN} max={THEME_DARK_LIGHTNESS_MAX} onChange={appearance.onDarkLightness} disabled={glassDisabled || theme != null}/>
        </Row>
      </Group>

      <Group title={t("Fonts")} description={t("Omarchy uses one monospace font everywhere. Pick one of its fonts here, or type the name of any font installed on this computer.")}>
        <Row id="code-font" label={t("Code font")} description={t("Code blocks, file paths and anything set in monospace.")}>
          <FontSelect label={t("Code font")} value={appearance.codeFont} emptyLabel="System monospace" monospaceOnly onChange={appearance.onCodeFont}/>
        </Row>
        <Row id="interface-font" label={t("Interface font")} description={t("Chat, menus and notes.")}>
          <FontSelect label={t("Interface font")} value={appearance.uiFont} emptyLabel="System default" followLabel="Same as code font" onChange={appearance.onUiFont}/>
        </Row>
      </Group>

      <Group title={t("Translucency")} description={glassDisabled
            ? t("Light mode always uses an opaque window, so these are off. Your dark-mode values are preserved.")
            : t("How much of the desktop shows through Loci. Blur costs more to composite the higher it goes.")}>
        <Row id="sidebar-opacity" label={t("Sidebar opacity")} description={t("Applies to the project rail and the other glass panes.")}>
          <Slider label={t("Sidebar opacity")} value={percent} display={`${percent}%`} min={Math.round(SIDEBAR_OPACITY_MIN * 100)} max={Math.round(SIDEBAR_OPACITY_MAX * 100)} onChange={appearance.onOpacity} disabled={glassDisabled}/>
        </Row>
        <Row id="blur" label={t("Blur radius")} description={t("Background blur behind the window.")}>
          <Slider label={t("Blur radius")} value={appearance.blur} display={String(appearance.blur)} min={SIDEBAR_BLUR_MIN} max={SIDEBAR_BLUR_MAX} onChange={appearance.onBlur} disabled={glassDisabled}/>
        </Row>
        <Row id="main-pane-glass" label={t("Main pane glass")} description={t("Extend the translucent treatment to the main pane behind sessions.")}>
          <Toggle label={t("Main pane glass")} on={appearance.bodyGlass} onChange={appearance.onBodyGlass} disabled={glassDisabled}/>
        </Row>
      </Group>

      <ChatBackgroundCard appearance={appearance}/>

      <Group title={t("Layout")}>
        <Row id="collapsed-project-rail" label={t("Collapsed project rail")} description={t("Keep project navigation available as a compact icon rail, or hide the rail completely.")}>
          <Segmented label={t("Collapsed project rail")} value={appearance.collapsedProjectRailMode} options={[
            { value: "compact", label: t("Icon rail") },
            { value: "hidden", label: t("Hidden") },
        ]} onChange={appearance.onCollapsedProjectRailMode}/>
        </Row>
        <Row id="interface-scale" label={t("Interface scale")} description={t("Zoom the whole interface. You can also use Ctrl+=, Ctrl+-, and Ctrl+0 (Cmd on macOS).")}>
          <Select label={t("Interface scale")} value={String(Math.round(appearance.uiScale * 100))} options={UI_SCALE_PERCENTS.map((percent) => ({
            value: String(percent),
            label: `${percent}%`,
        }))} onChange={(value) => appearance.onUiScale(Number(value))}/>
        </Row>

      </Group>
    </>);
}
function ChatBackgroundCard({ appearance, }: {
    appearance: AppearanceSettings;
}) {
  useLocale();
    const src = chatBackgroundSrc(appearance.chatBackgroundPath);
    const hasImage = Boolean(appearance.chatBackgroundPath && src);
    const emptyVisibility = Math.round(appearance.chatBackgroundEmptyOpacity * 100);
    const sessionVisibility = Math.round(appearance.chatBackgroundSessionOpacity * 100);
    const busy = appearance.chatBackgroundBusy;
    const theme = findTheme(appearance.themeId);
    return (<Group id="chat-background" title={t("Chat background")} description={t("An image behind your chat panes. It stays on this device.")}>
      {theme && theme.wallpapers.length > 0 ? (<WallpaperStrip theme={theme} selectedPath={appearance.chatBackgroundPath} onSelect={appearance.onSelectThemeWallpaper}/>) : null}
      <div className="border-b border-content/5 p-4 last:border-b-0">
        <div className="overflow-hidden rounded-lg border border-content/10">
          {hasImage ? (<div className={`relative h-36 ${appearance.newThreadBackgroundEffect === "gradient-blur" ? "bg-background-base" : ""}`}>
              {appearance.newThreadBackgroundEffect === "gradient-blur" ? (<GradientBlurBackground className="gradient-blur-preview absolute inset-0" style={{ opacity: appearance.chatBackgroundEmptyOpacity }}/>) : (<div aria-hidden className="size-full bg-cover bg-center bg-no-repeat" style={{
                    backgroundImage: "var(--chat-background-image)",
                    opacity: appearance.chatBackgroundEmptyOpacity,
                }}/>)}
              <span className="pointer-events-none absolute bottom-2 left-2 text-[11px] text-content/40">
                {t("Empty chat preview at")}{" "}{emptyVisibility}%
              </span>
            </div>) : (<button type="button" onClick={() => void appearance.onChooseChatBackground()} disabled={busy} className="flex h-36 w-full flex-col items-center justify-center gap-2 text-content/40 hover:bg-content/5 hover:text-content/70 disabled:cursor-default disabled:opacity-40">
              {busy ? (<Loader className="size-5 animate-spin" aria-hidden/>) : (<ImagePlus className="size-5" aria-hidden/>)}
              <span className="text-[12px]">{t("Choose an image")}</span>
            </button>)}
        </div>
        {hasImage ? (<div className="mt-3 flex items-center justify-end gap-2">
            <SecondaryButton onClick={() => void appearance.onChooseChatBackground()} disabled={busy}>
              {busy ? (<Loader className="size-3.5 animate-spin" aria-hidden/>) : null}
              {t("Change")}</SecondaryButton>
            <SecondaryButton onClick={() => void appearance.onClearChatBackground()} disabled={busy} danger>
              {t("Remove")}</SecondaryButton>
          </div>) : null}
        {appearance.chatBackgroundError ? (<p className="mt-2 text-[12px] text-red-400">
            {appearance.chatBackgroundError}
          </p>) : null}
      </div>
      {hasImage ? (<>
          <Row label={t("Background effect")} description={t(NEW_THREAD_BACKGROUND_EFFECT_DESCRIPTIONS[appearance.newThreadBackgroundEffect])}>
            <Segmented label={t("Background effect")} value={appearance.newThreadBackgroundEffect} options={NEW_THREAD_BACKGROUND_EFFECTS.map((effect) => ({
                value: effect,
                label: t(NEW_THREAD_BACKGROUND_EFFECT_LABELS[effect]),
            }))} onChange={appearance.onNewThreadBackgroundEffect} optionIdPrefix="new-thread-background-effect"/>
          </Row>
          <Row label={t("Show on")} description={t("Empty sessions only, or every conversation.")}>
            <Segmented label={t("Show background on")} value={appearance.chatBackgroundScope} options={[
                { value: "empty", label: t("Empty only") },
                { value: "all", label: t("All sessions") },
            ]} onChange={appearance.onChatBackgroundScope}/>
          </Row>
          <Row label={t("Empty chat visibility")} description={t("Background strength before a chat has messages.")}>
            <Slider label={t("Empty chat background visibility")} value={emptyVisibility} display={`${emptyVisibility}%`} min={Math.round(CHAT_BACKGROUND_OPACITY_MIN * 100)} max={Math.round(CHAT_BACKGROUND_OPACITY_MAX * 100)} onChange={appearance.onChatBackgroundEmptyOpacity}/>
          </Row>
          <Row label={t("Session visibility")} description={t("Background strength once the conversation has messages.")}>
            <Slider label={t("Session background visibility")} value={sessionVisibility} display={`${sessionVisibility}%`} min={Math.round(CHAT_BACKGROUND_OPACITY_MIN * 100)} max={Math.round(CHAT_BACKGROUND_OPACITY_MAX * 100)} onChange={appearance.onChatBackgroundSessionOpacity}/>
          </Row>
        </>) : null}
    </Group>);
}
type ShortcutModifier = "metaKey" | "ctrlKey" | "altKey" | "shiftKey";
function shortcutModifier(event: KeyboardEvent): ShortcutModifier | null {
    if (event.key === "Meta" || event.code.startsWith("Meta"))
        return "metaKey";
    if (event.key === "Control" || event.code.startsWith("Control"))
        return "ctrlKey";
    if (event.key === "Alt" || event.code.startsWith("Alt"))
        return "altKey";
    if (event.key === "Shift" || event.code.startsWith("Shift"))
        return "shiftKey";
    return null;
}
function ShortcutEditor({ name, display, resetVisible, onApply, onDisable, onReset, }: {
    name: string;
    display: string | null;
    resetVisible: boolean;
    onApply: (shortcut: string) => void | Promise<void>;
    onDisable: () => void | Promise<void>;
    onReset: () => void | Promise<void>;
}) {
  useLocale();
    const [recording, setRecording] = useState(false);
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [preview, setPreview] = useState("");
    const held = useRef({
        metaKey: false,
        ctrlKey: false,
        altKey: false,
        shiftKey: false,
    });
    const run = async (action: () => void | Promise<void>) => {
        setRecording(false);
        setBusy(true);
        setError(null);
        try {
            await action();
        }
        catch (reason) {
            setError(String(reason));
        }
        finally {
            setBusy(false);
        }
    };
    const beginRecording = () => {
        held.current = {
            metaKey: false,
            ctrlKey: false,
            altKey: false,
            shiftKey: false,
        };
        setPreview("");
        setError(null);
        setRecording(true);
    };
    useEffect(() => {
        if (!recording)
            return;
        const onKeyDown = (event: KeyboardEvent) => {
            const bare = !event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey;
            // An unmodified Tab leaves the recorder instead of trapping focus.
            if (bare && event.code === "Tab") {
                setRecording(false);
                return;
            }
            event.preventDefault();
            event.stopImmediatePropagation();
            if (event.code === "Escape") {
                setRecording(false);
                setError(null);
                return;
            }
            // Delete disables, but only on its own so Cmd+Delete still records.
            if (bare && (event.code === "Backspace" || event.code === "Delete")) {
                void run(onDisable);
                return;
            }
            const modifier = shortcutModifier(event);
            if (modifier)
                held.current[modifier] = true;
            const modifiers = {
                metaKey: event.metaKey || held.current.metaKey,
                ctrlKey: event.ctrlKey || held.current.ctrlKey,
                altKey: event.altKey || held.current.altKey,
                shiftKey: event.shiftKey || held.current.shiftKey,
            };
            setPreview(shortcutPreview(modifiers, modifier ? undefined : event.code, event.key));
            if (modifier)
                return;
            const next = shortcutFromKeyEvent({ ...modifiers, code: event.code });
            if (next)
                void run(() => onApply(next));
        };
        const onKeyUp = (event: KeyboardEvent) => {
            const modifier = shortcutModifier(event);
            if (!modifier)
                return;
            event.preventDefault();
            event.stopImmediatePropagation();
            held.current[modifier] = false;
            const modifiers = {
                metaKey: event.metaKey || held.current.metaKey,
                ctrlKey: event.ctrlKey || held.current.ctrlKey,
                altKey: event.altKey || held.current.altKey,
                shiftKey: event.shiftKey || held.current.shiftKey,
            };
            modifiers[modifier] = false;
            setPreview(shortcutPreview(modifiers));
        };
        window.addEventListener("keydown", onKeyDown, true);
        window.addEventListener("keyup", onKeyUp, true);
        return () => {
            window.removeEventListener("keydown", onKeyDown, true);
            window.removeEventListener("keyup", onKeyUp, true);
        };
    }, [onApply, onDisable, recording]);
    return (<div className="relative w-40 shrink-0">
      <div className="flex items-center gap-0.5">
        <input type="text" readOnly aria-label={t("Change {0} shortcut", name)} data-shortcut-recorder-active={recording ? "true" : undefined} aria-busy={busy || undefined} value={recording || busy ? preview || t("Record…") : (display ?? t("Disabled"))} onFocus={beginRecording} onClick={beginRecording} onBlur={() => setRecording(false)} className={`h-6 w-28 shrink-0 truncate rounded-md border bg-transparent px-1.5 py-0 font-mono text-[11px] leading-none outline-none focus:border-accent ${busy ? "opacity-50" : ""} ${display === null
            ? "border-dashed border-content/15 text-content/35"
            : "border-content/15 text-content/80 hover:bg-content/10"}`}/>
        {resetVisible ? (<button type="button" aria-label={t("Reset {0} shortcut", name)} disabled={busy} onClick={() => void run(onReset)} className="rounded-md px-1 py-1 text-content/35 hover:bg-content/10 hover:text-content disabled:opacity-50">
            <RotateCcw className="size-3.5"/>
          </button>) : null}
      </div>
      {recording ? (<p className="pointer-events-none absolute top-1/2 right-full z-40 mr-3 -translate-y-1/2 text-[10px] whitespace-nowrap text-content/50" aria-live="polite">
          {t("Del disables · Esc cancels")}</p>) : null}
      {error ? (<p role="alert" className="absolute top-full left-0 z-40 mt-1.5 w-max max-w-64 rounded-md border border-content/10 bg-background-base/95 px-2 py-1 text-[11px] whitespace-nowrap text-red-400 shadow-lg">
          {error}
        </p>) : null}
    </div>);
}
function KeybindingShortcutEditor({ command, display, modified, onSave, }: {
    command: string;
    display: string | null;
    modified: boolean;
    onSave: (command: string, override: KeybindingOverride) => void | Promise<void>;
}) {
  useLocale();
    return (<ShortcutEditor name={t(command)} display={display} resetVisible={modified} onApply={(shortcut) => onSave(command, { shortcut })} onDisable={() => onSave(command, { disabled: true })} onReset={() => onSave(command, {})}/>);
}
function KeybindingsPage() {
  useLocale();
    const [query, setQuery] = useState("");
    const [overrides, setOverrides] = useState(loadKeybindingOverrides);
    useEffect(() => subscribeKeybindings(() => setOverrides(loadKeybindingOverrides())), []);
    const rows = useMemo(() => filterKeybindings(currentKeybindings(), query), [getLocale(), query, overrides]);
    const save = async (command: string, override: KeybindingOverride) => {
        const next = saveKeybindingOverride(command, override);
        if (IS_MAC)
            await invoke("keybindings_set_overrides", { overrides: next });
    };
    return (<Group title={t("Shortcuts")} description={t("Click a shortcut to record new keys. Press Delete while recording to disable it.")} action={<div className="flex items-center gap-3">
          <span className="shrink-0 text-[12px] text-content/40 tabular-nums">
            {rows.length} {rows.length === 1 ? "binding" : "bindings"}
          </span>
          <label className="flex h-7 w-44 shrink-0 items-center gap-2 rounded-md border border-content/10 px-2 text-content/45 focus-within:border-content/20">
            <Search className="size-3.5 shrink-0" strokeWidth={1.75}/>
            <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={t("Filter")} aria-label={t("Filter keybindings")} spellCheck={false} autoComplete="off" className="min-w-0 flex-1 bg-transparent text-[12px] text-content outline-none placeholder:text-content/35"/>
          </label>
        </div>}>
      <div className="flex items-center border-b border-stroke bg-content/5 px-4 py-2 text-[11px] font-semibold uppercase tracking-[0.08em] text-content/40">
        <span className="min-w-0 flex-1">{t("Command")}</span>
        <span className="w-40 shrink-0">{t("Keybinding")}</span>
        <span className="w-28 shrink-0">{t("When")}</span>
      </div>
      {rows.length === 0 ? (<p className="px-4 py-3 text-[12px] text-content/45">
          {t("No matching bindings")}</p>) : (rows.map((row) => {
            const override = overrides[row.command];
            const disabled = override?.disabled === true;
            return (<div key={row.command} className="flex h-11 items-center border-b border-content/5 px-4 text-[12px] last:border-b-0">
              <span className={`min-w-0 flex-1 truncate ${disabled ? "text-content/45" : ""}`}>
                {t(row.command)}
              </span>
              {(<KeybindingShortcutEditor command={row.command} display={disabled ? null : row.keys} modified={Boolean(override)} onSave={save}/>)}
              <span className="w-28 shrink-0 font-mono text-[11px] text-content/40">
                {t(row.when)}
              </span>
            </div>);
        }))}
    </Group>);
}
const GLOBAL_PROVIDER_SCOPE = "global";
function binaryInspectionError(provider: ConfigurableBinaryProvider, inspection: HarnessBinaryInspection): string | null {
    if (inspection.error)
        return inspection.error;
    if (provider === "codex" && !/^codex-cli\s+\d+\.\d+\.\d+/.test(inspection.version ?? "")) {
        return t("Codex CLI returned an invalid version.");
    }
    return null;
}
function ProviderBinaryControl({ provider, }: {
    provider: ConfigurableBinaryProvider;
}) {
  useLocale();
    const root = useRef<HTMLSpanElement>(null);
    const trigger = useRef<HTMLButtonElement>(null);
    const editInput = useRef<HTMLInputElement>(null);
    const [open, setOpen] = useState(false);
    const [editing, setEditing] = useState(false);
    const [draft, setDraft] = useState(() => loadProviderBinaryPath(provider) ?? "");
    const [overridden, setOverridden] = useState(() => Boolean(loadProviderBinaryPath(provider)));
    const [inspection, setInspection] = useState<HarnessBinaryInspection & {
        overridden: boolean;
    }>();
    const [working, setWorking] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [revealError, setRevealError] = useState<string | null>(null);
    const inspect = useCallback(async (binaryPath?: string | null) => {
        setWorking(true);
        setInspection(undefined);
        setError(null);
        setRevealError(null);
        try {
            const next = await inspectHarnessBinary(provider, binaryPath);
            setInspection({
                ...next,
                overridden: Boolean(binaryPath?.trim()),
            });
            setError(binaryInspectionError(provider, next));
            return next;
        }
        catch (cause) {
            const message = cause instanceof Error ? cause.message : String(cause);
            setError(message);
            return null;
        }
        finally {
            setWorking(false);
        }
    }, [provider]);
    useEffect(() => {
        if (editing)
            editInput.current?.focus();
    }, [editing]);
    const dismiss = (restoreFocus = false) => {
        setOpen(false);
        setEditing(false);
        if (restoreFocus)
            queueMicrotask(() => trigger.current?.focus());
    };
    const submit = async (event: FormEvent<HTMLFormElement>) => {
        event.preventDefault();
        if (working)
            return;
        const value = draft.trim();
        if (!value) {
            await useAuto();
            return;
        }
        const next = await inspect(value);
        if (!next)
            return;
        const validationError = binaryInspectionError(provider, next);
        if (validationError) {
            setError(validationError);
            return;
        }
        if (!saveProviderBinaryPath(provider, value)) {
            setInspection(undefined);
            setError(t("Could not save the binary path."));
            return;
        }
        setOverridden(true);
        dismiss(true);
    };
    const useAuto = async () => {
        if (working)
            return;
        const next = await inspect(null);
        if (!next || binaryInspectionError(provider, next))
            return;
        if (!saveProviderBinaryPath(provider, null)) {
            setInspection(undefined);
            setError(t("Could not save the binary path."));
            return;
        }
        setDraft("");
        setOverridden(false);
        dismiss(true);
    };
    const title = HARNESS_TITLE[provider];
    const restartRequired = providerBinaryPathChangePending(provider);
    return (<span ref={root} className="inline-flex align-middle">
      <button ref={trigger} type="button" aria-label={restartRequired
            ? t("Show {0} CLI details, restart required", title)
            : t("Show {0} CLI details", title)} aria-expanded={open} aria-controls={`${provider}-binary-popover`} aria-haspopup="dialog" title={t("{0} CLI path{1}", title, restartRequired ? " — restart required" : "")} onClick={() => {
            if (!open && !inspection && !working && !error) {
                void inspect(loadProviderBinaryPath(provider));
            }
            setOpen((value) => !value);
            setEditing(false);
        }} className={`grid size-6 place-items-center rounded hover:bg-content/10 focus-visible:outline-2 focus-visible:outline-accent ${restartRequired ? "text-amber-300" : "text-content/35 hover:text-content"}`}>
        <FolderOpen className="size-3.5" strokeWidth={1.75}/>
      </button>
      {open ? (<Popover id={`${provider}-binary-popover`} role="dialog" aria-label={t("{0} CLI details", title)} aria-busy={working} tabIndex={-1} anchor={root} side="bottom" align="start" width={440} className="p-3" autoFocus onKeyDown={(event) => {
                if (event.key !== "Tab")
                    return;
                const focusable = Array.from(event.currentTarget.querySelectorAll<HTMLElement>('button:not([disabled]), input:not([disabled]), [href], [tabindex]:not([tabindex="-1"])'));
                const first = focusable[0];
                const last = focusable[focusable.length - 1];
                if (!first || !last)
                    return;
                if (event.shiftKey && document.activeElement === first) {
                    event.preventDefault();
                    last.focus();
                }
                else if (!event.shiftKey && document.activeElement === last) {
                    event.preventDefault();
                    first.focus();
                }
            }} onDismiss={(reason) => dismiss(reason === "escape")}>
          <div className="flex items-center justify-between gap-3">
            <span className="text-[12px] font-medium text-content">
              {title} CLI
            </span>
            <div className="flex items-center gap-1.5">
              <span className="rounded-full bg-content/10 px-1.5 py-0.5 text-[10px] text-content/50">
                {t("Global path")}</span>
              <span className="rounded-full bg-content/10 px-1.5 py-0.5 text-[10px] text-content/50">
                {error
                ? t("Needs attention")
                : restartRequired
                    ? t("Restart required")
                    : overridden
                        ? t("Configured")
                        : t("Auto-detected")}
              </span>
            </div>
          </div>
          {editing ? (<form className="mt-2" onSubmit={submit}>
              <label htmlFor={`${provider}-binary-path`} className="text-[11px] text-content/50">
                {t("CLI path")}</label>
              <input id={`${provider}-binary-path`} ref={editInput} type="text" value={draft} placeholder={inspection?.path ?? t("Auto-detected path")} disabled={working} autoFocus onChange={(event) => setDraft(event.target.value)} className="mt-1.5 h-8 w-full rounded-md border border-content/10 bg-content/[0.04] px-2 font-mono text-[11px] text-content outline-none placeholder:font-sans placeholder:text-content/35 focus:border-accent/45 disabled:opacity-50"/>
              <p className="mt-1.5 text-[10px] text-content/40">
                {t("Enter the absolute path to the CLI executable. Changes apply after restarting Loci.")}
              </p>
              {error ? (<span role="alert" className="mt-1.5 block text-[11px] text-red-400">
                  {error}
                </span>) : null}
              <div className="mt-3 flex justify-end gap-2">
                <SecondaryButton disabled={working} onClick={() => {
                    setDraft(loadProviderBinaryPath(provider) ?? "");
                    setEditing(false);
                    queueMicrotask(() => trigger.current?.focus());
                }}>
                  {t("Cancel")}</SecondaryButton>
                {overridden ? (<SecondaryButton disabled={working} onClick={() => void useAuto()}>
                    {t("Use auto-detected path")}</SecondaryButton>) : null}
                <SecondaryButton type="submit" disabled={working}>
                  {t("Save path")}</SecondaryButton>
              </div>
            </form>) : (<>
              <div className="mt-2 rounded-md border border-content/10 bg-content/[0.03] px-2.5 py-2">
                <span className="block max-h-12 overflow-y-auto whitespace-pre-wrap break-all font-mono text-[10px] text-content/65">
                  {inspection?.path ??
                    (error ? t("CLI could not be resolved") : t("Checking the selected CLI…"))}
                </span>
                <span className="mt-1 block max-h-10 overflow-y-auto whitespace-pre-wrap break-words text-[10px] text-content/40">
                  {inspection?.version ??
                    (error ? t("Retry to check this CLI") : t("Checking version…"))}
                </span>
              </div>
               {error ? (<span role="alert" title={error} className="mt-1.5 block max-h-20 overflow-y-auto whitespace-pre-wrap break-words text-[10px] leading-4 text-red-400">
                   {error}
                 </span>) : null}
               {revealError ? (<span role="alert" className="mt-1.5 block max-h-20 overflow-y-auto whitespace-pre-wrap break-words text-[10px] leading-4 text-red-400">
                   {t("Could not open the CLI location:")}{" "}{revealError}
                 </span>) : null}
               <div className="mt-3 flex justify-end gap-2">
                {error ? (<SecondaryButton disabled={working} aria-label={t("Retry {0} {1}", title, overridden ? "configured path" : "auto-detect")} onClick={() => void inspect(overridden ? draft.trim() || null : null)}>
                    <RefreshCw className="size-3.5" strokeWidth={1.75}/>
                    {overridden ? t("Retry configured path") : t("Retry auto-detect")}
                  </SecondaryButton>) : null}
                <SecondaryButton aria-label={t("Open {0} CLI location", title)} disabled={!inspection} onClick={() => {
                    if (inspection) {
                        void revealPath(inspection.path).catch((cause) => {
                            setRevealError(cause instanceof Error ? cause.message : String(cause));
                        });
                    }
                }}>
                  <ExternalLink className="size-3.5" strokeWidth={1.75}/>
                  {t("Open location")}</SecondaryButton>
                <SecondaryButton aria-label={t("Edit {0} CLI path", title)} disabled={working} onClick={() => setEditing(true)}>
                  <Pencil className="size-3.5" strokeWidth={1.75}/>
                  {t("Edit path")}</SecondaryButton>
              </div>
            </>)}
        </Popover>) : null}
    </span>);
}
function ProvidersPage({ cwd, recents, }: {
    cwd?: string;
    recents?: RecentProject[];
}) {
  useLocale();
    useSyncExternalStore(subscribeModels, getModelSnapshot, getModelSnapshot);
    useSyncExternalStore(subscribeHarnessAvailability, getHarnessAvailabilitySnapshot, getHarnessAvailabilitySnapshot);
    const providersRevision = useSyncExternalStore(subscribeProjectProviders, projectProvidersRevision, projectProvidersRevision);
    void providersRevision;
    const [choice, setChoice] = useState(loadLastModelChoice);
    const [defaultModels, setDefaultModels] = useState(loadDefaultModels);
    const [claudeHooks, setClaudeHooks] = useState(loadClaudeHooks);
    const [scope, setScope] = useState<string>(GLOBAL_PROVIDER_SCOPE);
    const [hiddenGlobally, setHiddenGlobally] = useState(loadHiddenPickerProviders);
    const scopeOptions = useMemo(() => {
        const options: {
            value: string;
            label: string;
            icon?: ReactNode;
        }[] = [
            {
                value: GLOBAL_PROVIDER_SCOPE,
                label: t("Global"),
                icon: (<Globe className="size-3.5 shrink-0 text-content/60" strokeWidth={1.75}/>),
            },
        ];
        const seen = new Set<string>();
        for (const path of [cwd, ...(recents ?? []).map((entry) => entry.path)]) {
            if (!path || !looksLikeProject(path))
                continue;
            const key = pathKey(path);
            if (seen.has(key))
                continue;
            seen.add(key);
            options.push({
                value: path,
                label: projectName(path),
                icon: <ProjectScopeIcon path={path}/>,
            });
        }
        return options;
    }, [getLocale(), cwd, recents]);
    const project = scope === GLOBAL_PROVIDER_SCOPE ? null : scope;
    const projectSettings = project ? loadProjectProviderSettings(project) : {};
    // A project without overrides inherits the global default provider, the same
    // way `defaultSessionChoice` resolves it for new conversations.
    const effectiveDefaultHarness = project
        ? firstEnabledHarness(project, projectSettings.defaultHarness ?? choice?.harness ?? "claude")
        : (choice?.harness ?? null);
    useEffect(() => {
        void probeHarnessAvailability();
    }, []);
    useEffect(() => {
        if (!scopeOptions.some((option) => option.value === scope)) {
            setScope(GLOBAL_PROVIDER_SCOPE);
        }
    }, [scope, scopeOptions]);
    const onClaudeHooks = (next: boolean) => {
        saveClaudeHooks(next);
        setClaudeHooks(next);
    };
    const onModelChange = (harness: HarnessId, model: string) => {
        if (project) {
            setProjectDefaultModel(project, harness, model);
            return;
        }
        saveDefaultModel(harness, model);
        setDefaultModels((prev) => ({ ...prev, [harness]: model }));
        if (choice?.harness === harness) {
            saveLastModelChoice(harness, model);
            setChoice({ harness, model });
        }
    };
    const onDefault = (harness: HarnessId, model: string) => {
        if (project) {
            setProjectDefaultProvider(project, harness, model);
            return;
        }
        saveLastModelChoice(harness, model);
        setDefaultModels((prev) => ({ ...prev, [harness]: model }));
        setChoice({ harness, model });
    };
    const onPickerVisible = (harness: HarnessId, visible: boolean) => {
        if (project) {
            setProjectProviderHidden(project, harness, !visible);
            return;
        }
        savePickerProviderVisible(harness, visible);
        setHiddenGlobally((prev) => visible
            ? prev.filter((id) => id !== harness)
            : [...new Set([...prev, harness])]);
    };
    return (<>
      <ProviderAccountsSettings />

      <UsageDisplaySettings />

      <Group id="agent-clis" title={t("Agent CLIs")} action={<Select label={t("Provider defaults scope")} value={scope} options={scopeOptions} onChange={setScope}/>} description={project
            ? t("These defaults apply to {0} only. A provider with Show in picker off is also kept out of new conversations started in this project. CLI paths remain global for Loci.", projectName(project))
            : "A provider is listed as installed once its CLI is found on your PATH. Uninstalled CLIs stay listed but are left out of the model picker, as are installed ones with Show in picker off. The model beside a provider is what its new conversations start with; Use by default picks the provider itself. CLI paths are global for Loci and apply to every project."}>
        {HARNESSES.map((harness) => {
            const inPicker = project
                ? !(projectSettings.hidden ?? []).includes(harness) &&
                    !hiddenGlobally.includes(harness)
                : !hiddenGlobally.includes(harness);
            // A globally hidden provider stays out of every project's picker, so
            // the project toggle is shown locked rather than appearing to work.
            const pickerLocked = project != null && hiddenGlobally.includes(harness);
            const selectedModel = project
                ? (projectSettings.models?.[harness] ??
                    (projectSettings.defaultHarness === harness
                        ? projectSettings.defaultModel
                        : undefined) ??
                    defaultModels[harness] ??
                    (choice?.harness === harness
                        ? choice.model
                        : defaultModelId(harness)))
                : (defaultModels[harness] ??
                    (choice?.harness === harness
                        ? choice.model
                        : defaultModelId(harness)));
            const isDefault = project
                ? effectiveDefaultHarness === harness
                : choice?.harness === harness;
            return (<ProviderRow key={harness} harness={harness} selectedModel={selectedModel} isDefault={isDefault} inPicker={inPicker} pickerLocked={pickerLocked} onDefault={onDefault} onModelChange={onModelChange} onPickerVisible={(visible) => onPickerVisible(harness, visible)}/>);
        })}
      </Group>

      <Group title={t("Advanced")}>
        <Row id="claude-hooks" label={t("Claude Code hooks")} description={t("Run the hooks configured in your settings.json files — PreToolUse command rewrites, blocks, notifications, and the rest — just as the Claude Code CLI would. Turn this off if a hook is misbehaving and you need the session back. Takes effect on the next turn.")}>
          <Toggle label={t("Claude Code hooks")} on={claudeHooks} onChange={onClaudeHooks}/>
        </Row>
      </Group>
    </>);
}
function UsageDisplaySettings() {
  useLocale();
    const showRemainingUsage = useShowRemainingUsage();
    const maskEmails = useMaskEmails();
    return (<Group title={t("Usage and privacy")}>
      <Row id="show-remaining-usage" label={t("Show remaining usage")} description={t("Fill usage meters with what is left in each limit instead of what has been used.")}>
        <Toggle label={t("Show remaining usage")} on={showRemainingUsage} onChange={saveShowRemainingUsage}/>
      </Row>
      <Row id="mask-emails" label={t("Mask account emails")} description={t("Blur account emails in Settings and the usage popover until you click one, so they stay out of screenshots.")}>
        <Toggle label={t("Mask account emails")} on={maskEmails} onChange={saveMaskEmails}/>
      </Row>
    </Group>);
}
type AccountEditor = {
    provider: ProviderAccountProvider;
    accountId?: string;
    label: string;
};
function ProviderAccountsSettings() {
  useLocale();
    const [version, setVersion] = useState(0);
    const [editor, setEditor] = useState<AccountEditor | null>(null);
    const [working, setWorking] = useState<string | null>(null);
    const [error, setError] = useState<string | null>(null);
    useEffect(() => subscribeProviderAccounts(() => setVersion((value) => value + 1)), []);
    const startAdd = (provider: ProviderAccountProvider) => {
        setError(null);
        setEditor({ provider, label: "" });
    };
    const startRename = (account: ProviderAccount) => {
        setError(null);
        setEditor({
            provider: account.provider,
            accountId: account.id,
            label: account.label,
        });
    };
    const submitEditor = async (event: FormEvent<HTMLFormElement>) => {
        event.preventDefault();
        if (!editor || !editor.label.trim() || working)
            return;
        const key = editor.accountId
            ? `rename:${editor.provider}:${editor.accountId}`
            : `add:${editor.provider}`;
        setWorking(key);
        setError(null);
        try {
            if (editor.accountId) {
                renameProviderAccount(editor.provider, editor.accountId, editor.label);
            }
            else {
                const account = newProviderAccount(editor.provider, editor.label);
                await loginHarness(editor.provider, account.id);
                saveProviderAccount(account);
            }
            setEditor(null);
        }
        catch (caught) {
            setError(caught instanceof Error
                ? caught.message
                : t("Could not save this account"));
        }
        finally {
            setWorking(null);
        }
    };
    const removeAccount = async (account: ProviderAccount) => {
        if (account.isDefault || working)
            return;
        const confirmed = await ask(t("Remove “{0}”? Its stored credentials will be deleted and any running turns for this account will stop. Existing conversations stay in history, but cannot continue until you switch accounts.", account.label), {
            title: t("Remove {0} account", HARNESS_TITLE[account.provider]),
            kind: "warning",
            okLabel: t("Remove account"),
            cancelLabel: t("Cancel"),
        });
        if (!confirmed)
            return;
        const key = `remove:${account.provider}:${account.id}`;
        setWorking(key);
        setError(null);
        try {
            await removeProviderAccountCredentials(account.provider, account.id);
            removeProviderAccount(account.provider, account.id);
            clearCachedRateLimits(account.provider, account.id);
            if (editor?.provider === account.provider &&
                editor.accountId === account.id) {
                setEditor(null);
            }
        }
        catch (caught) {
            setError(caught instanceof Error
                ? caught.message
                : t("Could not remove this account"));
        }
        finally {
            setWorking(null);
        }
    };
    const identities = useProviderAccountIdentities(PROVIDER_ACCOUNT_PROVIDERS.flatMap(providerAccounts), version);
    const usage = useProviderAccountUsage(version);
    return (<Group id="provider-accounts" title={t("Accounts")} description={t("Create isolated sign-ins for providers that support account profiles. Account switching stays available from the usage control in the footer.")} action={<AccountUsageRefresh usage={usage}/>}>
      {PROVIDER_ACCOUNT_PROVIDERS.map((provider) => {
            const accounts = providerAccounts(provider);
            const adding = editor?.provider === provider && !editor.accountId;
            return (<div key={provider} className="border-b border-content/5 last:border-b-0">
            <div className="flex items-center gap-4 px-4 py-3.5">
              <div className="flex min-w-0 flex-1 items-center gap-2.5">
                <span className="grid size-7 shrink-0 place-items-center rounded-lg bg-content/[0.05] ring-1 ring-inset ring-content/[0.06]">
                  <HarnessIcon harness={provider} className="size-4"/>
                </span>
                <div className="min-w-0">
                  <div className="text-[13px] font-medium text-content">
                    {HARNESS_TITLE[provider]}
                  </div>
                  <div className="mt-0.5 text-[11px] text-content/40">
                    {accounts.length}{" "}
                    {accounts.length === 1 ? "account" : "accounts"}
                  </div>
                </div>
              </div>
              <button type="button" disabled={Boolean(working)} onClick={() => startAdd(provider)} className="flex shrink-0 items-center gap-1.5 rounded-md border border-content/10 px-2.5 py-1 text-[12px] text-content/70 transition-transform duration-150 hover:bg-content/10 hover:text-content active:scale-[0.97] disabled:cursor-default disabled:opacity-40">
                <Plus className="size-3.5" strokeWidth={1.75} aria-hidden/>
                {t("Add account")}</button>
            </div>
            <div className="border-t border-content/5 bg-content/[0.015] pl-10">
              {accounts.map((account) => {
                    const editing = editor?.provider === provider &&
                        editor.accountId === account.id;
                    const removing = working === `remove:${provider}:${account.id}`;
                    const identity = identities[identityKey(account)];
                    const orgTag = identityOrganizationTag(identity);
                    const limits = usage.usage[accountUsageKey(account)];
                    return editing ? (<ProviderAccountEditor key={account.id} editor={editor} working={Boolean(working)} onLabel={(label) => setEditor((current) => current ? { ...current, label } : current)} onCancel={() => setEditor(null)} onSubmit={submitEditor}/>) : (<div key={account.id} className="flex h-12 items-center gap-3 border-b border-content/5 px-4 py-2 last:border-b-0">
                    <div className="min-w-0 flex-1">
                      <div className="flex min-w-0 items-center gap-1.5">
                        <span className="truncate text-[12px] text-content/85">
                          {account.label}
                        </span>
                        {orgTag ? (<span className="max-w-[8rem] shrink-0 truncate rounded bg-content/[0.07] px-1 text-[9px] leading-4 text-content/50">
                            {orgTag}
                          </span>) : null}
                      </div>
                      <div className="mt-0.5 flex min-w-0 items-center gap-2.5 text-[10px]">
                        <AccountStatusLabel status={accountStatus(limits, usage.now)} className="shrink-0"/>
                        <ProviderAccountSubtitle identity={identity} fallback={account.isDefault
                            ? t("Provider CLI profile")
                            : t("Isolated profile")} className="truncate text-content/30"/>
                      </div>
                    </div>
                    <AccountUsageMeters limits={limits} now={usage.now}/>
                    <div className="flex w-24 shrink-0 items-center justify-end gap-1">
                      {account.isDefault ? (<span className="mr-1 text-[10px] font-medium uppercase tracking-wide text-content/30">
                          {t("Default")}</span>) : null}
                      <button type="button" disabled={Boolean(working)} aria-label={t("Rename {0}", account.label)} title={t("Rename account")} onClick={() => startRename(account)} className="grid size-7 place-items-center rounded-md text-content/40 transition-transform duration-150 hover:bg-content/10 hover:text-content active:scale-[0.96] disabled:opacity-35">
                        <Pencil className="size-3.5" strokeWidth={1.75}/>
                      </button>
                      {!account.isDefault ? (<button type="button" disabled={Boolean(working)} aria-label={t("Remove {0}", account.label)} title={t("Remove account")} onClick={() => void removeAccount(account)} className="grid size-7 place-items-center rounded-md text-content/35 transition-transform duration-150 hover:bg-red-400/10 hover:text-red-400 active:scale-[0.96] disabled:opacity-35">
                          {removing ? (<Loader className="size-3.5 animate-spin"/>) : (<Trash2 className="size-3.5" strokeWidth={1.75}/>)}
                        </button>) : null}
                    </div>
                  </div>);
                })}
              {adding && editor ? (<ProviderAccountEditor editor={editor} working={Boolean(working)} onLabel={(label) => setEditor((current) => current ? { ...current, label } : current)} onCancel={() => setEditor(null)} onSubmit={submitEditor}/>) : null}
            </div>
          </div>);
        })}
      {error ? (<p className="border-t border-content/5 px-4 py-2.5 text-[11px] leading-4 text-red-400" role="alert">
          {error}
        </p>) : null}
    </Group>);
}
function ProviderAccountEditor({ editor, working, onLabel, onCancel, onSubmit, }: {
    editor: AccountEditor;
    working: boolean;
    onLabel: (label: string) => void;
    onCancel: () => void;
    onSubmit: (event: FormEvent<HTMLFormElement>) => void;
}) {
  useLocale();
    const adding = !editor.accountId;
    return (<form className="flex h-12 items-center border-b border-content/5 px-4 py-2 last:border-b-0" onSubmit={onSubmit}>
      <div data-provider-account-editor-field className="flex items-center pr-1 h-8 min-w-0 flex-1 overflow-hidden rounded-md border border-content/10 bg-content/[0.04] focus-within:border-accent/45">
        <label className="h-full min-w-0 flex-1">
          <span className="sr-only">{t("Account name")}</span>
          <input autoFocus type="text" maxLength={48} value={editor.label} disabled={working} placeholder={t("Work or Personal")} aria-label={t("{0} {1} account", adding ? "New" : "Rename", HARNESS_TITLE[editor.provider])} onChange={(event) => onLabel(event.target.value)} className="h-full w-full bg-transparent px-2.5 text-[12px] text-content outline-none placeholder:text-content/25 disabled:opacity-50"/>
        </label>
        <button type="button" disabled={working} onClick={onCancel} className="flex h-6 shrink-0 items-center rounded-[4.5px] bg-content/[0.05] px-2.5 text-[11px] text-content/45 transition-transform duration-150 hover:bg-content/10 hover:text-content active:scale-[0.97] disabled:opacity-40">
          {t("Cancel")}</button>
        <button type="submit" disabled={working || !editor.label.trim()} className="ml-1 flex h-6 shrink-0 items-center gap-1.5 rounded-[4.5px] bg-content px-2.5 text-[11px] font-medium text-background-base transition-transform duration-150 hover:bg-content/85 active:scale-[0.97] disabled:cursor-default disabled:opacity-40">
          {working ? <Loader className="size-3 animate-spin"/> : null}
          {adding
            ? working
                ? t("Waiting for browser…")
                : t("Sign in and add")
            : t("Save")}
        </button>
      </div>
    </form>);
}
/** The icon the project rail shows: custom logo, else the project mascot. */
function ProjectScopeIcon({ path }: {
    path: string;
}) {
  useLocale();
    const logos = useTabGroupLogos();
    const [colors] = useState(loadTabGroupColors);
    const [customColors] = useState(loadTabGroupCustomColors);
    const [mascots] = useState(loadTabGroupMascots);
    const key = projectKey(path);
    const name = projectName(path);
    const logoPath = resolveTabGroupLogo(key, logos);
    if (logoPath) {
        return (<ProjectLogoIcon path={logoPath} className="size-4 rounded-sm" imageClassName="size-4"/>);
    }
    return (<ProjectMascot project={name} color={resolveTabGroupColor(key, colors, customColors, name)} name={resolveTabGroupMascot(key, mascots)} className="size-3.5"/>);
}
function ProviderRow({ harness, selectedModel, isDefault, inPicker, pickerLocked = false, onDefault, onModelChange, onPickerVisible, }: {
    harness: HarnessId;
    selectedModel: string;
    isDefault: boolean;
    inPicker: boolean;
    /** Globally hidden providers cannot be turned on per project. */
    pickerLocked?: boolean;
    onDefault: (harness: HarnessId, model: string) => void;
    onModelChange: (harness: HarnessId, model: string) => void;
    onPickerVisible: (visible: boolean) => void;
}) {
  useLocale();
    const models = modelsFor(harness);
    const available = isHarnessAvailable(harness);
    const current = models.length > 0 ? resolveModel(harness, selectedModel) : null;
    useEffect(() => {
        if (!available || hasLiveCatalog(harness))
            return;
        void refreshHarnessCatalogs([harness]);
    }, [available, harness]);
    return (<Row label={<span className="flex items-center gap-2">
          <HarnessIcon harness={harness} className="size-4 shrink-0"/>
          {HARNESS_TITLE[harness]}
          <ProviderBinaryControl provider={harness}/>
          {isDefault ? (<span className="rounded-full bg-content/10 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-content/60">
              {t("Default")}</span>) : null}
        </span>} description={available
            ? t("{0} {1} available.", models.length, models.length === 1 ? "model" : "models")
            : harnessUnavailableHint(harness)}>
      {current ? (<Select label={t("{0} model", HARNESS_TITLE[harness])} value={current.id} onChange={(next) => onModelChange(harness, next)} options={models.map((item) => ({
                value: item.id,
                label: item.name,
            }))}/>) : null}
      <SecondaryButton onClick={() => current && onDefault(harness, current.id)} disabled={isDefault || !current}>
        {isDefault ? t("Default") : t("Use by default")}
      </SecondaryButton>
      {available ? (<div className="flex items-center gap-2">
          <span className="text-[12px] text-content/50">
            {pickerLocked ? t("Hidden globally") : t("Show in picker")}
          </span>
          <Toggle label={t("Show {0} in the model picker", HARNESS_TITLE[harness])} on={inPicker} onChange={onPickerVisible} disabled={pickerLocked}/>
        </div>) : null}
    </Row>);
}
function useArchivedProjects(): ArchivedProject[] {
  useLocale();
    const [items, setItems] = useState(loadArchivedProjects);
    useEffect(() => subscribeArchivedProjects(() => setItems(loadArchivedProjects())), []);
    return items;
}
function archivedProjectLabel(path: string): string {
    return resolveTabGroupLabel(projectKey(path), loadTabGroupLabels(), projectName(path));
}
function ArchivePage({ cwd, sessions, onOpenSession, onArchiveSession, onDeleteSession, onRestoreProject, onDeleteProject, }: {
    cwd: string;
    sessions: SessionSummary[];
    onOpenSession: (sessionId: string) => void;
    onArchiveSession: (sessionId: string, archived: boolean) => void;
    onDeleteSession: (sessionId: string) => void;
    onRestoreProject?: (path: string) => void;
    onDeleteProject?: (path: string) => void;
}) {
  useLocale();
    const [filters, setFilters] = useState(loadSessionSidebarFilters);
    const [deleting, setDeleting] = useState<ArchivedProject | null>(null);
    const archivedProjects = useArchivedProjects();
    const archived = useMemo(() => sessions
        .filter((session) => session.archived)
        .sort((a, b) => b.updatedAt - a.updatedAt), [getLocale(), sessions]);
    const onShowArchived = (showArchived: boolean) => {
        const next = { ...filters, showArchived };
        saveSessionSidebarFilters(next);
        setFilters(next);
    };
    return (<>
      <Group title={t("Archived projects")} description={t("Archive a project from the rail to keep its chats without listing it in the sidebar.")}>
        {archivedProjects.length === 0 ? (<p className="px-4 py-3.5 text-[12px] text-content/45">
            {t("No archived projects.")}</p>) : (archivedProjects.map((project) => (<div key={project.path} className="flex items-center gap-3 border-b border-content/5 px-4 py-2.5 last:border-b-0">
              <div className="min-w-0 flex-1">
                <div className="truncate text-[13px]">
                  {archivedProjectLabel(project.path)}
                </div>
                <div className="truncate text-[11px] text-content/40">
                  {prettyCwd(project.path)}
                </div>
              </div>
              {onRestoreProject ? (<SecondaryButton onClick={() => onRestoreProject(project.path)}>
                  {t("Restore")}</SecondaryButton>) : null}
              {onDeleteProject ? (<SecondaryButton danger onClick={() => setDeleting(project)}>
                  {t("Delete")}</SecondaryButton>) : null}
            </div>)))}
      </Group>

      <Group title={looksLikeProject(cwd)
            ? t("Archived in {0}", projectName(cwd))
            : t("Archived conversations")}>
        <Row id="show-archived" label={t("Show archived in the sidebar")} description={t("Keep archived conversations listed alongside the active ones.")}>
          <Toggle label={t("Show archived in the sidebar")} on={filters.showArchived} onChange={onShowArchived}/>
        </Row>
        {!looksLikeProject(cwd) ? (<p className="px-4 py-3.5 text-[12px] text-content/45">
            {t("Open a project to see its archived conversations.")}</p>) : archived.length === 0 ? (<p className="px-4 py-3.5 text-[12px] text-content/45">
            {t("No archived conversations in this project.")}</p>) : (archived.map((session) => (<div key={session.id} className="flex items-center gap-3 border-b border-content/5 px-4 py-2.5 last:border-b-0">
              <HarnessIcon harness={session.harness} className="size-3.5 shrink-0"/>
              <button type="button" onClick={() => onOpenSession(session.id)} className="min-w-0 flex-1 truncate text-left text-[13px] hover:text-content">
                {sessionDisplayTitle(session.title, session.harness)}
              </button>
              <span className="shrink-0 text-[11px] text-content/35 tabular-nums">
                {formatDate(session.updatedAt)}
              </span>
              <SecondaryButton onClick={() => onArchiveSession(session.id, false)}>
                {t("Unarchive")}</SecondaryButton>
              <SecondaryButton danger onClick={() => onDeleteSession(session.id)}>
                {t("Delete")}</SecondaryButton>
            </div>)))}
      </Group>

      {deleting ? (<RemoveProjectDialog name={archivedProjectLabel(deleting.path)} path={deleting.path} onCancel={() => setDeleting(null)} onConfirm={() => {
                onDeleteProject?.(deleting.path);
                setDeleting(null);
            }}/>) : null}
    </>);
}
function formatDate(value: number): string {
    if (!Number.isFinite(value) || value <= 0)
        return "";
    try {
        return new Intl.DateTimeFormat(getLocale(), {
            month: "short",
            day: "numeric",
        }).format(new Date(value));
    }
    catch {
        return "";
    }
}
function PageHeader({ title, description, }: {
    title: string;
    description: string;
}) {
  useLocale();
    return (<header className="pb-4">
      <h1 className="text-[20px] font-semibold leading-tight text-content">
        {title}
      </h1>
      {description ? (<p className="mt-1.5 max-w-xl text-[13px] leading-relaxed text-content/45">
          {description}
        </p>) : null}
    </header>);
}
/**
 * A titled card of related settings. Everything on a page lives in one, so a
 * page reads as a handful of topics instead of one long list of switches.
 */
/** The agents the user has, and whether the app shows them at all. */
function AgentsPage() {
    useLocale();
    const enabled = useSyncExternalStore(subscribeAgentsEnabled, loadAgentsEnabled, () => true);
    const snapshot = useSyncExternalStore(subscribeAgents, agentsSnapshot);
    // eslint-disable-next-line react-hooks/exhaustive-deps
    const agents = useMemo(() => listAgents(), [snapshot]);
    const templateSnapshot = useSyncExternalStore(subscribeAgentTemplates, agentTemplatesSnapshot, () => "");
    // eslint-disable-next-line react-hooks/exhaustive-deps
    const templates = useMemo(() => listAgentTemplates(), [templateSnapshot]);
    return (<>
      <Group title={t("Agents")}>
        <Row id="agents-enabled" label={t("Show agents")} description={t("Long-lived agents on the project rail, each with its own conversation, memory and habits. Turning this off hides them and pauses their habits; nothing is deleted.")}>
          <Toggle label={t("Show agents")} on={enabled} onChange={saveAgentsEnabled}/>
        </Row>
      </Group>
      <Group id="agent-list" title={t("Your agents")} description={t("Add an agent with the plus beside Agents on the project rail. Its model, projects, soul, habits and memory are set in its Details panel.")}>
        {agents.length ? agents.map((agent) => <AgentRow key={agent.id} agent={agent}/>) : (<p className="px-4 py-3.5 text-[12px] text-content/45">{t("No agents yet.")}</p>)}
      </Group>
      <Group id="agent-templates" title={t("Agent templates")} description={t("A template is an agent with its soul already written. Picking one writes this soul into the new agent's SOUL.md, and nothing else is sent to it. Changes apply to agents made afterwards.")}>
        {templates.map((template) => <TemplateRow key={template.id} template={template}/>)}
      </Group>
    </>);
}
const TEMPLATE_FIELD_CLASS = "mt-1 block w-full rounded-md border border-stroke bg-background-base px-2 py-1.5 text-[13px] text-content outline-none focus:border-content/30";
/** One built-in template: its wording, open to edit, with the way back to what ships. */
function TemplateRow({ template }: { template: AgentTemplate }) {
    useLocale();
    const [draft, setDraft] = useState<Record<TemplateTextField, string>>();
    const edited = agentTemplateEdited(template.id);
    const open = () => setDraft(Object.fromEntries(TEMPLATE_TEXT_FIELDS.map((field) => [field, template[field] ?? ""])) as Record<TemplateTextField, string>);
    const set = (field: TemplateTextField) => (event: { target: { value: string } }) => setDraft((current) => current && ({ ...current, [field]: event.target.value }));
    const reset = async () => {
        if (!await ask(t("Your changes to this template are discarded. Agents already made from it keep their own soul."), { title: t("Reset {0} to its defaults?", template.name), kind: "warning", okLabel: t("Reset"), cancelLabel: t("Cancel") }))
            return;
        resetAgentTemplate(template.id);
        setDraft(undefined);
    };
    const line = (field: TemplateTextField, label: string) => (<label className="block text-xs text-content/65">
          {label}<input value={draft?.[field] ?? ""} onChange={set(field)} spellCheck={false} className={TEMPLATE_FIELD_CLASS}/>
        </label>);
    const text = (field: TemplateTextField, label: string, hint: string, rows: number, mono = false) => (<label className="block text-xs text-content/65">
          {label}<span className="ml-1.5 text-content/40">{hint}</span>
          <textarea value={draft?.[field] ?? ""} onChange={set(field)} rows={rows} spellCheck={false} className={`${TEMPLATE_FIELD_CLASS} resize-y leading-relaxed ${mono ? "font-mono text-xs" : ""}`}/>
        </label>);
    return (<div data-template={template.id} className="border-b border-content/5 last:border-b-0">
      <Row label={<span className="flex min-w-0 items-center gap-2">
            <AgentAvatar name={template.avatar} color={template.color} className="size-4 shrink-0"/>
            <span className="truncate">{template.name}</span>
            {edited ? <span className="shrink-0 rounded bg-content/10 px-1.5 py-px text-[10px] font-normal text-content/55">{t("Edited")}</span> : null}
          </span>} description={template.description}>
        {edited ? <SecondaryButton onClick={() => void reset()}>{t("Reset")}</SecondaryButton> : null}
        <SecondaryButton onClick={() => draft ? setDraft(undefined) : open()}>{draft ? t("Cancel") : t("Edit")}</SecondaryButton>
      </Row>
      {draft ? (<div className="flex flex-col gap-3 px-4 pb-4">
          <div className="grid grid-cols-2 gap-3">
            {line("name", t("Name"))}
            {line("role", t("Role"))}
          </div>
          {line("description", t("Line in the menu"))}
          {text("soul", t("Soul"), t("Written into the new agent's SOUL.md. It is everything that makes it this kind of agent."), 18, true)}
          <div className="flex justify-end gap-2">
            <SecondaryButton onClick={() => setDraft(undefined)}>{t("Cancel")}</SecondaryButton>
            <button type="button" className="primary-action rounded-md px-3 py-1 text-xs font-medium" onClick={() => { saveAgentTemplate(template.id, draft); setDraft(undefined); }}>{t("Save")}</button>
          </div>
        </div>) : null}
    </div>);
}
function AgentRow({ agent }: { agent: Agent }) {
    useLocale();
    const look = agentLook(agent);
    const [error, setError] = useState<string>();
    const reset = async () => {
        if (!await ask(t("Its soul goes back to the default and its name to {0}. Changes to its soul can't be recovered. Its conversation, projects, memory and habits are kept.", defaultAgentName(look.avatar)), { title: t("Reset {0} to its defaults?", look.name), kind: "warning", okLabel: t("Reset"), cancelLabel: t("Cancel") }))
            return;
        await resetAgentDefaults(agent.id).then(() => setError(undefined), (reason: unknown) => setError(reason instanceof Error ? reason.message : String(reason)));
    };
    return (<Row label={<span className="flex min-w-0 items-center gap-2">
          <AgentAvatar name={look.avatar} color={look.color} className="size-4 shrink-0"/>
          <span className="truncate">{look.name}</span>
        </span>} description={error ?? (look.projects.length ? t("Works on {0}", agentProjectsPhrase(look.projects)) : t("No projects yet"))}>
      <SecondaryButton onClick={() => void reset()}>{t("Reset")}</SecondaryButton>
    </Row>);
}
function Group({ id, title, description, action, children, }: {
    /** Matches a `SETTINGS_INDEX` id when the whole card is the search target. */
    id?: string;
    title: ReactNode;
    description?: string;
    action?: ReactNode;
    children: ReactNode;
}) {
  useLocale();
    const revealed = useContext(RevealedSetting);
    const flash = id != null && revealed === id;
    return (<section id={id ? settingDomId(id) : undefined} data-setting-id={id} className="pt-8 first:pt-0">
      <div className="flex items-end gap-4 pb-2.5">
        <div className="min-w-0 flex-1">
          <h2 className="text-[13px] font-semibold text-content">{title}</h2>
          {description ? (<p className="mt-1 text-[12px] leading-relaxed text-content/45">
              {description}
            </p>) : null}
        </div>
        {action ? <div className="shrink-0 pb-0.5">{action}</div> : null}
      </div>
      <div className={`overflow-hidden rounded-xl border bg-content/3 transition-colors ${flash ? "border-accent/60" : "border-content/10"}`}>
        {children}
      </div>
    </section>);
}
function Row({ id, label, description, children, }: {
    /** Matches a `SETTINGS_INDEX` id so search can scroll here. */
    id?: string;
    label: ReactNode;
    description?: string;
    children?: ReactNode;
}) {
  useLocale();
    const revealed = useContext(RevealedSetting);
    const flash = id != null && revealed === id;
    return (<div id={id ? settingDomId(id) : undefined} data-setting-id={id} className={`settings-row flex items-start gap-6 border-b border-content/5 px-4 py-3.5 transition-colors last:border-b-0 ${flash ? "bg-accent/10" : ""}`}>
      <div className="min-w-0 flex-1">
        <div className="text-[13px] font-medium text-content">{label}</div>
        {description ? (<p className="mt-1 text-[12px] leading-relaxed text-content/45">
            {description}
          </p>) : null}
      </div>
      <div className="settings-row-control flex min-w-0 max-w-[60%] shrink-0 flex-wrap items-center justify-end gap-2">
        {children}
      </div>
    </div>);
}
/** A row whose control needs the full width, such as the theme gallery. */
function BlockRow({ id, label, description, children, }: {
    id?: string;
    label: ReactNode;
    description?: string;
    children: ReactNode;
}) {
  useLocale();
    const revealed = useContext(RevealedSetting);
    const flash = id != null && revealed === id;
    return (<div id={id ? settingDomId(id) : undefined} data-setting-id={id} className={`border-b border-content/5 px-4 py-3.5 transition-colors last:border-b-0 ${flash ? "bg-accent/10" : ""}`}>
      <div className="text-[13px] font-medium text-content">{label}</div>
      {description ? (<p className="mt-1 text-[12px] leading-relaxed text-content/45">
          {description}
        </p>) : null}
      <div className="mt-3">{children}</div>
    </div>);
}
const CUSTOM_FONT = "__custom";
/**
 * A font choice: the system's, one of Omarchy's, or any family a person types.
 * Typed names are checked before they are kept. A code font that does not come
 * out as monospace (it is not installed, or it is not a code font) is not
 * applied, and the row says so.
 */
function FontSelect({ label, value, emptyLabel, followLabel, monospaceOnly = false, onChange, }: {
    label: string;
    value: string | null;
    emptyLabel: string;
    /** Offered for the interface font: use whatever the code font is. */
    followLabel?: string;
    /** The code font: it has to render as monospace to be used. */
    monospaceOnly?: boolean;
    onChange: (value: string | null) => void;
}) {
  useLocale();
    const preset = OMARCHY_FONTS.find((font) => font.family === value);
    const selected = value == null ? "" : value === UI_FONT_FOLLOWS_CODE ? value : preset ? preset.family : CUSTOM_FONT;
    const [custom, setCustom] = useState(selected === CUSTOM_FONT);
    const [draft, setDraft] = useState(selected === CUSTOM_FONT ? (value ?? "") : "");
    const [invalid, setInvalid] = useState(false);
    useEffect(() => {
        setCustom(selected === CUSTOM_FONT);
        setInvalid(false);
        if (selected === CUSTOM_FONT)
            setDraft(value ?? "");
        else
            setDraft("");
    }, [selected, value]);
    const options = [
        { value: "", label: emptyLabel },
        ...(followLabel ? [{ value: UI_FONT_FOLLOWS_CODE, label: followLabel }] : []),
        ...OMARCHY_FONTS.map((font) => ({ value: font.family, label: font.label })),
        { value: CUSTOM_FONT, label: t("Custom…") },
    ];
    const commit = () => {
        if (draft.trim() === "") {
            setInvalid(false);
            return;
        }
        const next = normalizeFontFamily(draft);
        setInvalid(next == null);
        if (next != null && next !== value)
            onChange(next);
    };
    const unusable = monospaceOnly && value != null && value !== UI_FONT_FOLLOWS_CODE && rendersMonospace(value) === false;
    return (<div className="flex w-52 max-w-full flex-col items-stretch gap-1.5">
      <Select label={label} value={custom ? CUSTOM_FONT : selected} options={options} onChange={(next) => {
            setInvalid(false);
            if (next === CUSTOM_FONT) {
                setCustom(true);
                return;
            }
            setCustom(false);
            onChange(next === "" ? null : next);
        }}/>
      {custom ? (<input type="text" aria-label={t("{0} name", label)} aria-invalid={invalid || undefined} value={draft} placeholder={t("Font name, e.g. Fira Code")} spellCheck={false} autoCapitalize="off" autoComplete="off" onChange={(event) => {
                setDraft(event.target.value);
                setInvalid(false);
            }} onBlur={commit} onKeyDown={(event) => {
                if (event.key === "Enter") {
                    event.preventDefault();
                    commit();
                }
            }} className={`w-full rounded-md border bg-content/5 px-2 py-1 text-[12px] text-content outline-none placeholder:text-content/30 focus:border-content/30 ${invalid ? "border-red-400/70" : "border-content/10"}`}/>) : null}
      {invalid ? (<p role="alert" className="text-[11px] text-red-400">
          {t("Use plain font names, such as Fira Code, monospace.")}</p>) : unusable ? (<p className="text-[11px] text-content/45">
          {t("Not installed, or not a monospace font, so the system monospace is used.")}</p>) : null}
    </div>);
}
function Segmented<T extends string>({ label, value, options, onChange, optionIdPrefix, disabled = false, }: {
    label: string;
    value: T;
    options: {
        value: T;
        label: string;
    }[];
    onChange: (value: T) => void;
    optionIdPrefix?: string;
    disabled?: boolean;
}) {
  useLocale();
    return (<div role="radiogroup" aria-label={label} aria-disabled={disabled || undefined} className={`inline-grid max-w-full shrink-0 gap-0.5 rounded-md border border-content/10 p-0.5 text-[12px] ${disabled ? "opacity-40" : ""}`} style={{
            gridTemplateColumns: `repeat(${options.length}, minmax(0, 1fr))`,
        }}>
      {options.map((option) => (<button id={optionIdPrefix
                ? `${optionIdPrefix}-${option.value.toLowerCase()}`
                : undefined} key={option.value} type="button" role="radio" aria-checked={value === option.value} disabled={disabled} onClick={() => onChange(option.value)} className={`min-w-0 rounded-[5px] px-2.5 py-1 disabled:cursor-not-allowed ${value === option.value
                ? "bg-selection text-content"
                : "text-content/50 hover:text-content"}`}>
          {option.label}
        </button>))}
    </div>);
}
function Slider({ label, value, display, min, max, step = 1, onChange, disabled = false, }: {
    label: string;
    value: number;
    display: string;
    min: number;
    max: number;
    step?: number;
    onChange: (value: number) => void;
    disabled?: boolean;
}) {
  useLocale();
    return (<div className={`flex w-56 max-w-full items-center gap-3 ${disabled ? "opacity-40" : ""}`}>
      <input type="range" min={min} max={max} step={step} value={value} aria-valuemin={min} aria-valuemax={max} aria-valuenow={value} aria-label={label} disabled={disabled} className="sidebar-opacity-slider min-w-0 flex-1 disabled:cursor-not-allowed" onChange={(event) => onChange(Number(event.target.value))}/>
      <span className="w-10 shrink-0 text-right text-[12px] text-content tabular-nums">
        {display}
      </span>
    </div>);
}
const ACCENT_COLOR_PRESETS = [
    "#4da3f5",
    "#8b5cf6",
    "#ec4899",
    "#ef4444",
    "#f59e0b",
    "#10b981",
] as const;
function AccentColorPicker({ value, themeAccent = null, onChange, }: {
    value: string | null;
    /** The accent the theme in effect picks; the first swatch stands for it while none is chosen. */
    themeAccent?: string | null;
    onChange: (value: string | null) => void;
}) {
  useLocale();
    const [open, setOpen] = useState(false);
    const root = useRef<HTMLDivElement>(null);
    const colorIndex = value
        ? ACCENT_COLOR_PRESETS.indexOf(value as (typeof ACCENT_COLOR_PRESETS)[number])
        : -1;
    const presetIndex = value == null ? 0 : colorIndex >= 0 ? colorIndex + 1 : -1;
    return (<div ref={root} className="w-48">
      <ColorSwatchRow colors={[themeAccent ?? "var(--color-content)", ...ACCENT_COLOR_PRESETS]} labels={[themeAccent ? t("Theme") : t("Default"), t("Blue"), t("Violet"), t("Pink"), t("Red"), t("Orange"), t("Green")]} colorIndex={presetIndex >= 0 ? presetIndex : undefined} customColor={presetIndex < 0 ? (value ?? undefined) : undefined} customPickerOpen={open} onPickIndex={(index) => {
            setOpen(false);
            onChange(index === 0
                ? ACCENT_COLOR_DEFAULT
                : (ACCENT_COLOR_PRESETS[index - 1] ?? ACCENT_COLOR_PRESETS[0]));
        }} onToggleCustom={() => setOpen((current) => !current)}/>
      {open ? (<Popover anchor={root} side="bottom" align="end" width={248} onDismiss={() => setOpen(false)} className="px-2 pb-2">
          <ColorPickerPopover value={value ?? ACCENT_COLOR_PRESETS[0]} onChange={onChange}/>
        </Popover>) : null}
    </div>);
}
/** macOS keeps the decision after the first prompt; only System Settings can flip it. Windows toasts are governed by Settings > Notifications. */
function NotificationsBlocked() {
  useLocale();
    return (<span className="flex items-center gap-2 text-[12px] text-content/45">
      {t("Permission needed")}{IS_MAC || IS_WIN ? (<button type="button" onClick={() => {
                void openNotificationSettings().catch(() => { });
            }} className="rounded-md border border-content/10 px-2 py-1 text-content/70 hover:bg-content/10 hover:text-content">
          {t("Open System Settings")}</button>) : null}
    </span>);
}
function Toggle({ label, on, onChange, disabled = false, }: {
    label: string;
    on: boolean;
    onChange: (on: boolean) => void;
    disabled?: boolean;
}) {
  useLocale();
    return (<button type="button" role="switch" aria-label={label} aria-checked={on} disabled={disabled} onClick={() => {
            onChange(!on);
            playCue("switch");
        }} className={`relative h-5 w-9 shrink-0 rounded-full transition-colors disabled:cursor-not-allowed disabled:opacity-40 ${on ? "bg-accent" : "bg-content/20"}`}>
      <span className={`absolute top-0.5 size-4 rounded-full bg-white transition-[left] ${on ? "left-4.5" : "left-0.5"}`}/>
    </button>);
}
/** Theme-aware dropdown for a Settings row: a trigger button opening a Popover listbox. Used instead of a native select, whose option popup is OS-rendered and unreadable in dark mode on Windows/Linux. */
function Select({ label, value, options, onChange, }: {
    label: string;
    value: string;
    options: {
        value: string;
        label: string;
        icon?: ReactNode;
    }[];
    onChange: (value: string) => void;
}) {
  useLocale();
    const [open, setOpen] = useState(false);
    const [active, setActive] = useState(() => Math.max(0, options.findIndex((option) => option.value === value)));
    const root = useRef<HTMLDivElement>(null);
    const trigger = useRef<HTMLButtonElement>(null);
    const activeOption = useRef<HTMLButtonElement>(null);
    const listId = useId();
    const selected = options.find((option) => option.value === value);
    const activeId = options[active] != null ? `${listId}-opt-${active}` : undefined;
    useEffect(() => {
        if (!open)
            return;
        setActive(Math.max(0, options.findIndex((option) => option.value === value)));
    }, [open, value, options]);
    useEffect(() => {
        if (!open)
            return;
        activeOption.current?.scrollIntoView({ block: "nearest" });
    }, [active, open]);
    const pick = (next: string) => {
        onChange(next);
        setOpen(false);
        trigger.current?.focus();
    };
    const onMenuKey = (e: ReactKeyboardEvent<HTMLDivElement>) => {
        if (e.key === "ArrowDown") {
            e.preventDefault();
            setActive((i) => Math.min(options.length - 1, i + 1));
            return;
        }
        if (e.key === "ArrowUp") {
            e.preventDefault();
            setActive((i) => Math.max(0, i - 1));
            return;
        }
        if (e.key === "Home") {
            e.preventDefault();
            setActive(0);
            return;
        }
        if (e.key === "End") {
            e.preventDefault();
            setActive(options.length - 1);
            return;
        }
        if (e.key === "Tab") {
            const option = options[active];
            if (option && option.value !== value)
                onChange(option.value);
            setOpen(false);
            trigger.current?.focus();
            return;
        }
        if (e.key === "Enter") {
            e.preventDefault();
            const option = options[active];
            if (option)
                pick(option.value);
        }
    };
    return (<div ref={root} className="relative max-w-52">
      <button type="button" ref={trigger} aria-label={`${label}: ${selected?.label ?? value}`} aria-expanded={open} aria-haspopup="listbox" onClick={() => setOpen((prev) => !prev)} className="flex w-full items-center justify-between gap-2 rounded-md border border-content/10 bg-content/5 px-2 py-1 text-left text-[12px] text-content outline-none hover:border-content/20">
        <span className="flex min-w-0 flex-1 items-center gap-1.5">
          {selected?.icon ? (<span className="grid size-4 shrink-0 place-items-center">
              {selected.icon}
            </span>) : null}
          <span className="min-w-0 truncate">
            {selected ? selected.label : value}
          </span>
        </span>
        <ChevronDown className={`size-3.5 shrink-0 text-content/50 transition-transform ${open ? "rotate-180" : ""}`} strokeWidth={1.75}/>
      </button>
      {open ? (<Popover anchor={root} side="bottom" align="end" width={280} maxHeight={320} autoFocus onDismiss={(reason) => {
                setOpen(false);
                if (reason === "escape")
                    trigger.current?.focus();
            }} role="listbox" aria-label={label} aria-activedescendant={activeId} tabIndex={-1} onKeyDown={onMenuKey} className="overflow-y-auto overscroll-contain p-1">
          {options.map((option, index) => {
                const isSelected = option.value === value;
                const highlighted = index === active;
                return (<button key={option.value} ref={highlighted ? activeOption : undefined} type="button" id={`${listId}-opt-${index}`} role="option" tabIndex={-1} aria-selected={isSelected} onMouseDown={(e) => e.preventDefault()} onMouseEnter={() => setActive(index)} onClick={() => pick(option.value)} className={`flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-[12px] ${highlighted || isSelected
                        ? "bg-selection text-content"
                        : "text-content hover:bg-content/5"}`}>
                {option.icon ? (<span className="grid size-4 shrink-0 place-items-center">
                    {option.icon}
                  </span>) : null}
                <span className="min-w-0 flex-1 truncate">{option.label}</span>
                {isSelected ? (<Check className="size-3.5 shrink-0" strokeWidth={2.25}/>) : null}
              </button>);
            })}
        </Popover>) : null}
    </div>);
}

function VersionRow() {
  useLocale();
 const [version,setVersion] = useState("…");
 useEffect(()=>{let cancelled=false;void getVersion().then(next=>{if(!cancelled)setVersion(next)}).catch(()=>{if(!cancelled)setVersion(t("Unavailable"))});return ()=>{cancelled=true}},[]);
 return <Row id="version" label={<span className="flex items-baseline gap-2">{t("Version")}<span className="font-mono text-[12px] text-content/45">{version}</span></span>} description="Loci" />;
}
