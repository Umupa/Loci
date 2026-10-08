import { t, useLocale } from "../../shared/i18n/locale";
import { invoke } from "@tauri-apps/api/core";
import { useCallback, useEffect, useRef, useState } from "react";
import { ContextMenu, type ContextMenuItem, } from "../../shared/ui/ContextMenu";
import { ALT, MOD, SHIFT } from "../../platform/tauri/platform";
import { keybindingShortcutLabel, loadKeybindingOverrides, subscribeKeybindings, } from "../../features/settings/model/settings";
type MenuKey = "file" | "view";
type Props = {
    onNew: () => void;
    onSwitchTab?: () => void;
    onNextAttention?: () => void;
    onTabOverview?: () => void;
    onReopenTab?: () => void;
    onToggleSidebar: () => void;
    onToggleSessionSidebar: () => void;
    onCloseCurrentTab?: () => void;
    onCloseOtherTabs?: () => void;
    onCloseAllTabs?: () => void;
    onPickProject?: () => void;
    onSearch?: () => void;
    onOpenNotes?: () => void;
    onZoomIn?: () => void;
    onZoomOut?: () => void;
    onZoomReset?: () => void;
};
export function MenuBar({ onNew, onSwitchTab, onNextAttention, onTabOverview, onReopenTab, onToggleSidebar, onToggleSessionSidebar, onCloseCurrentTab, onCloseOtherTabs, onCloseAllTabs, onPickProject, onSearch, onOpenNotes, onZoomIn, onZoomOut, onZoomReset, }: Props) {
  useLocale();
    const [open, setOpen] = useState(false);
    const [activeMenu, setActiveMenu] = useState<MenuKey | null>(null);
    const [menuAnchor, setMenuAnchor] = useState<{
        x: number;
        y: number;
    } | null>(null);
    const [, refreshShortcuts] = useState(loadKeybindingOverrides);
    const barRef = useRef<HTMLDivElement>(null);
    useEffect(() => subscribeKeybindings(() => refreshShortcuts(loadKeybindingOverrides())), []);
    const shortcut = (command: string, keys: string) => keybindingShortcutLabel(command, keys) ?? undefined;
    // Toggle with standalone Alt key tap
    useEffect(() => {
        let altPressedAlone = false;
        const onKeyDown = (e: KeyboardEvent) => {
            if (e.key === "Alt") {
                altPressedAlone = true;
            }
            else if (altPressedAlone) {
                altPressedAlone = false;
            }
        };
        const onKeyUp = (e: KeyboardEvent) => {
            if (e.key === "Alt" && altPressedAlone) {
                setOpen((prev) => {
                    if (prev) {
                        setActiveMenu(null);
                        setMenuAnchor(null);
                        return false;
                    }
                    return true;
                });
                altPressedAlone = false;
            }
        };
        const onBlur = () => {
            altPressedAlone = false;
        };
        window.addEventListener("keydown", onKeyDown);
        window.addEventListener("keyup", onKeyUp);
        window.addEventListener("blur", onBlur);
        return () => {
            window.removeEventListener("keydown", onKeyDown);
            window.removeEventListener("keyup", onKeyUp);
            window.removeEventListener("blur", onBlur);
        };
    }, []);
    const openDropdown = useCallback((key: MenuKey, target: HTMLElement) => {
        const rect = target.getBoundingClientRect();
        setActiveMenu(key);
        setMenuAnchor({ x: rect.left, y: rect.bottom + 2 });
    }, []);
    const closeMenu = useCallback(() => {
        setActiveMenu(null);
        setMenuAnchor(null);
    }, []);
    const handlePick = useCallback((id: string) => {
        closeMenu();
        setOpen(false);
        switch (id) {
            case "new_tab":
                onNew();
                break;
            case "new_window":
                void invoke("open_new_window").catch(() => { });
                break;
            case "open_project":
                onPickProject?.();
                break;
            case "open_search":
                onSearch?.();
                break;
            case "open_notes":
                onOpenNotes?.();
                break;
            case "switch_tab":
                onSwitchTab?.();
                break;
            case "next_attention":
                onNextAttention?.();
                break;
            case "tab_overview":
                onTabOverview?.();
                break;
            case "reopen_tab":
                onReopenTab?.();
                break;
            case "close_tab":
                onCloseCurrentTab?.();
                break;
            case "close_other_tabs":
                onCloseOtherTabs?.();
                break;
            case "close_all_tabs":
                onCloseAllTabs?.();
                break;
            case "toggle_sidebar":
                onToggleSidebar();
                break;
            case "toggle_session_sidebar":
                onToggleSessionSidebar();
                break;
            case "open_model_picker":
                window.dispatchEvent(new Event("open_model_picker"));
                break;
            case "zoom_in":
                onZoomIn?.();
                break;
            case "zoom_out":
                onZoomOut?.();
                break;
            case "zoom_reset":
                onZoomReset?.();
                break;
        }
    }, [
        closeMenu,
        onSwitchTab,
        onNextAttention,
        onTabOverview,
        onReopenTab,
        onCloseCurrentTab,
        onCloseOtherTabs,
        onCloseAllTabs,
        onNew,
        onPickProject,
        onSearch,
        onOpenNotes,
        onToggleSidebar,
        onToggleSessionSidebar,
        onZoomIn,
        onZoomOut,
        onZoomReset,
    ]);
    const getMenuItems = (key: MenuKey): ContextMenuItem[] => {
        switch (key) {
            case "file":
                return [
                    {
                        kind: "item",
                        id: "new_tab",
                        label: t("New Tab"),
                        shortcut: shortcut("Tab: New", `${MOD}T`),
                    },
                    {
                        kind: "item",
                        id: "switch_tab",
                        label: t("Switch Tab…"),
                        shortcut: shortcut("Tab: Switch", `${MOD}P`),
                    },
                    {
                        kind: "item",
                        id: "next_attention",
                        label: t("Next Tab Needing You"),
                        shortcut: shortcut("Tab: Next Needing You", `${MOD}J`),
                    },
                    {
                        kind: "item",
                        id: "tab_overview",
                        label: t("Tab Overview"),
                        shortcut: shortcut("Tab: Overview", `${MOD}${SHIFT}O`),
                    },
                    {
                        kind: "item",
                        id: "reopen_tab",
                        label: t("Reopen Closed Tab"),
                        shortcut: shortcut("Tab: Reopen Closed", `${MOD}${SHIFT}T`),
                    },
                    {
                        kind: "item",
                        id: "new_window",
                        label: t("New Window"),
                        shortcut: shortcut("App: New Window", `${MOD}${SHIFT}N`),
                    },
                    { kind: "sep" },
                    {
                        kind: "item",
                        id: "open_project",
                        label: t("Open Project…"),
                        shortcut: shortcut("App: Open Project", `${MOD}O`),
                    },
                    {
                        kind: "item",
                        id: "open_search",
                        label: t("Search…"),
                        shortcut: shortcut("App: Search", `${MOD}K`),
                    },
                    { kind: "sep" },
                    {
                        kind: "item",
                        id: "close_tab",
                        label: t("Close Pane"),
                        shortcut: shortcut("Pane: Close", `${MOD}W`),
                    },
                    {
                        kind: "item",
                        id: "close_other_tabs",
                        label: t("Close Other Tabs"),
                        shortcut: shortcut("Tab: Close Others", `${MOD}${ALT}T`),
                    },
                    {
                        kind: "item",
                        id: "close_all_tabs",
                        label: t("Close All Tabs"),
                        shortcut: shortcut("Tab: Close All", `${MOD}${SHIFT}W`),
                    },
                ];
            case "view":
                return [
                    {
                        kind: "item",
                        id: "toggle_sidebar",
                        label: t("Toggle Sidebar"),
                        shortcut: shortcut("App: Toggle Sidebar", `${MOD}B`),
                    },
                    {
                        kind: "item",
                        id: "toggle_session_sidebar",
                        label: t("Toggle Session Sidebar"),
                        shortcut: shortcut("App: Toggle Session Sidebar", `${MOD}${SHIFT}B`),
                    },
                    ...(onOpenNotes
                        ? [{ kind: "item" as const, id: "open_notes", label: t("Notes") }]
                        : []),
                    {
                        kind: "item",
                        id: "open_model_picker",
                        label: t("Switch Model…"),
                        shortcut: shortcut("App: Switch Model", `${MOD}.`),
                    },
                    { kind: "sep" },
                    {
                        kind: "item",
                        id: "zoom_in",
                        label: t("Zoom In"),
                        shortcut: shortcut("View: Zoom In", `${MOD}+`),
                    },
                    {
                        kind: "item",
                        id: "zoom_out",
                        label: t("Zoom Out"),
                        shortcut: shortcut("View: Zoom Out", `${MOD}-`),
                    },
                    {
                        kind: "item",
                        id: "zoom_reset",
                        label: t("Reset Zoom"),
                        shortcut: shortcut("View: Reset Zoom", `${MOD}0`),
                    },
                ];
        }
    };
    if (!open && !activeMenu) {
        return null;
    }
    const MENUS: {
        key: MenuKey;
        label: string;
    }[] = [
        { key: "file", label: t("File") },
        { key: "view", label: t("View") },
    ];
    return (<div ref={barRef} className="flex h-7 shrink-0 items-center gap-0.5 border-b border-stroke bg-content/5 px-2 text-[12px]" data-tauri-drag-region="false">
      {MENUS.map(({ key, label }) => {
            const isActive = activeMenu === key;
            return (<button key={key} type="button" data-tauri-drag-region="false" onClick={(e) => {
                    if (isActive) {
                        closeMenu();
                    }
                    else {
                        openDropdown(key, e.currentTarget);
                    }
                }} onMouseEnter={(e) => {
                    if (activeMenu && activeMenu !== key) {
                        openDropdown(key, e.currentTarget);
                    }
                }} className={`rounded px-2 py-0.5 transition-colors ${isActive
                    ? "bg-selection-hover text-content"
                    : "text-content/70 hover:bg-content/10 hover:text-content"}`}>
            {label}
          </button>);
        })}

      {activeMenu && menuAnchor ? (<ContextMenu x={menuAnchor.x} y={menuAnchor.y} items={getMenuItems(activeMenu)} ariaLabel={t("{0} menu", activeMenu)} onPick={handlePick} onClose={closeMenu}/>) : null}
    </div>);
}
