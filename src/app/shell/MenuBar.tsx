import { invoke } from "@tauri-apps/api/core";
import { useCallback, useEffect, useRef, useState } from "react";
import { ContextMenu, type ContextMenuItem, } from "../../shared/ui/ContextMenu";
import { MOD, SHIFT } from "../../platform/tauri/platform";
import { keybindingShortcutLabel, loadKeybindingOverrides, subscribeKeybindings, } from "../../features/settings/model/settings";
type MenuKey = "file" | "view";
type Props = {
    onNewMentor: () => void;
    onCloseReader: () => void;
    onPreviousMentor: () => void;
    onNextMentor: () => void;
    onToggleLibrary: () => void;
    onToggleChat: () => void;
    onOpenPdf: () => void;
    onSearch?: () => void;
    onZoomIn: () => void;
    onZoomOut: () => void;
    onZoomReset: () => void;
};
/** The window menu where the system has none (Windows and Linux), shown with a tap of Alt. */
export function MenuBar({ onNewMentor, onCloseReader, onPreviousMentor, onNextMentor, onToggleLibrary, onToggleChat, onOpenPdf, onSearch, onZoomIn, onZoomOut, onZoomReset }: Props) {
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
            if (e.key === "Alt") altPressedAlone = true;
            else if (altPressedAlone) altPressedAlone = false;
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
        const onBlur = () => { altPressedAlone = false; };
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
    const actions: Record<string, (() => void) | undefined> = {
        new_mentor: onNewMentor,
        new_window: () => { void invoke("open_new_window").catch(() => { }); },
        open_pdf: onOpenPdf,
        open_search: onSearch,
        close_reader: onCloseReader,
        prev_mentor: onPreviousMentor,
        next_mentor: onNextMentor,
        toggle_library: onToggleLibrary,
        toggle_chat: onToggleChat,
        open_model_picker: () => window.dispatchEvent(new Event("open_model_picker")),
        zoom_in: onZoomIn,
        zoom_out: onZoomOut,
        zoom_reset: onZoomReset,
    };
    const handlePick = (id: string) => {
        closeMenu();
        setOpen(false);
        actions[id]?.();
    };
    const getMenuItems = (key: MenuKey): ContextMenuItem[] => key === "file" ? [
        { kind: "item", id: "new_mentor", label: "New Mentor…", shortcut: shortcut("Mentor: New", `${MOD}T`) },
        { kind: "item", id: "new_window", label: "New Window", shortcut: shortcut("App: New Window", `${MOD}${SHIFT}N`) },
        { kind: "item", id: "open_pdf", label: "Open PDF…" },
        ...(onSearch ? [{ kind: "item" as const, id: "open_search", label: "Search…", shortcut: shortcut("App: Search", `${MOD}K`) }] : []),
        { kind: "sep" },
        { kind: "item", id: "close_reader", label: "Close", shortcut: shortcut("Reader: Close", `${MOD}W`) },
        { kind: "sep" },
        { kind: "item", id: "prev_mentor", label: "Previous Mentor", shortcut: shortcut("Mentor: Previous", `${MOD}${SHIFT}[`) },
        { kind: "item", id: "next_mentor", label: "Next Mentor", shortcut: shortcut("Mentor: Next", `${MOD}${SHIFT}]`) },
    ] : [
        { kind: "item", id: "toggle_library", label: "Toggle Library", shortcut: shortcut("App: Toggle Library", `${MOD}B`) },
        { kind: "item", id: "toggle_chat", label: "Toggle Conversation", shortcut: shortcut("App: Toggle Conversation", `${MOD}${SHIFT}B`) },
        { kind: "item", id: "open_model_picker", label: "Switch Model…", shortcut: shortcut("App: Switch Model", `${MOD}.`) },
        { kind: "sep" },
        { kind: "item", id: "zoom_in", label: "Zoom In", shortcut: shortcut("View: Zoom In", `${MOD}+`) },
        { kind: "item", id: "zoom_out", label: "Zoom Out", shortcut: shortcut("View: Zoom Out", `${MOD}-`) },
        { kind: "item", id: "zoom_reset", label: "Reset Zoom", shortcut: shortcut("View: Reset Zoom", `${MOD}0`) },
    ];
    if (!open && !activeMenu) {
        return null;
    }
    const MENUS: {
        key: MenuKey;
        label: string;
    }[] = [
        { key: "file", label: "File" },
        { key: "view", label: "View" },
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

      {activeMenu && menuAnchor ? (<ContextMenu x={menuAnchor.x} y={menuAnchor.y} items={getMenuItems(activeMenu)} ariaLabel={`${activeMenu} menu`} onPick={handlePick} onClose={closeMenu}/>) : null}
    </div>);
}
