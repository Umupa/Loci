import { invoke } from "@tauri-apps/api/core";
import { useCallback, useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent } from "react";
import { ContextMenu, type ContextMenuItem, } from "../../shared/ui/ContextMenu";
import { LAYER } from "../../shared/lib/layers";
import { MOD, SHIFT } from "../../platform/tauri/platform";
import { keybindingShortcutLabel, loadKeybindingOverrides, subscribeKeybindings, } from "../../features/settings/model/settings";
type MenuKey = "file" | "view";
type Props = {
    onNewMentor: () => void;
    onCloseReader: () => void;
    onReaderBack?: () => void;
    onReaderForward?: () => void;
    onPreviousMentor: () => void;
    onNextMentor: () => void;
    onToggleLibrary: () => void;
    onToggleChat: () => void;
    onOpenPdf: () => void;
    onSearch?: () => void;
    onOpenSettings: () => void;
    onZoomIn: () => void;
    onZoomOut: () => void;
    onZoomReset: () => void;
};
/** The window menu where the system has none (Windows and Linux), shown with a tap of Alt. */
export function MenuBar({ onNewMentor, onCloseReader, onReaderBack, onReaderForward, onPreviousMentor, onNextMentor, onToggleLibrary, onToggleChat, onOpenPdf, onSearch, onOpenSettings, onZoomIn, onZoomOut, onZoomReset }: Props) {
    const [open, setOpen] = useState(false);
    const [activeMenu, setActiveMenu] = useState<MenuKey | null>(null);
    const [menuAnchor, setMenuAnchor] = useState<{
        x: number;
        y: number;
    } | null>(null);
    const [, refreshShortcuts] = useState(loadKeybindingOverrides);
    const barRef = useRef<HTMLDivElement>(null);
    const menuButtons = useRef(new Map<MenuKey, HTMLButtonElement>());
    /** Where focus was before the bar took it. */
    const previousFocus = useRef<HTMLElement | null>(null);
    const openRef = useRef(open);
    openRef.current = open;
    useEffect(() => subscribeKeybindings(() => refreshShortcuts(loadKeybindingOverrides())), []);
    const shortcut = (command: string, keys: string) => keybindingShortcutLabel(command, keys) ?? undefined;
    const showBar = useCallback(() => {
        previousFocus.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
        setOpen(true);
    }, []);
    const dismissBar = useCallback((restoreFocus: boolean) => {
        setActiveMenu(null);
        setMenuAnchor(null);
        setOpen(false);
        if (restoreFocus) previousFocus.current?.focus();
    }, []);
    // Toggle with standalone Alt key tap
    useEffect(() => {
        let altPressedAlone = false;
        const onKeyDown = (e: KeyboardEvent) => {
            if (e.key === "Alt") altPressedAlone = true;
            else if (altPressedAlone) altPressedAlone = false;
        };
        const onKeyUp = (e: KeyboardEvent) => {
            if (e.key === "Alt" && altPressedAlone) {
                altPressedAlone = false;
                if (openRef.current) dismissBar(true);
                else showBar();
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
    }, [dismissBar, showBar]);
    // A tap of Alt opens the bar on File, ready for the keys that drive a menu bar.
    useEffect(() => {
        if (open && !activeMenu) menuButtons.current.get("file")?.focus();
    }, [open, activeMenu]);
    // Escape puts the bar away before a dropdown handles it, and returns focus.
    useEffect(() => {
        if (!open) return;
        const onKey = (event: KeyboardEvent) => {
            if (event.key !== "Escape") return;
            event.preventDefault();
            event.stopImmediatePropagation();
            dismissBar(true);
        };
        window.addEventListener("keydown", onKey, true);
        return () => window.removeEventListener("keydown", onKey, true);
    }, [open, dismissBar]);
    // A click elsewhere puts the bar away.
    useEffect(() => {
        if (!open || activeMenu) return;
        const onPointerDown = (event: PointerEvent) => {
            if (barRef.current?.contains(event.target as Node)) return;
            dismissBar(false);
        };
        window.addEventListener("pointerdown", onPointerDown);
        return () => window.removeEventListener("pointerdown", onPointerDown);
    }, [open, activeMenu, dismissBar]);
    const openDropdown = useCallback((key: MenuKey, target: HTMLElement) => {
        const rect = target.getBoundingClientRect();
        setActiveMenu(key);
        setMenuAnchor({ x: rect.left, y: rect.bottom + 2 });
    }, []);
    const closeMenu = useCallback(() => {
        setActiveMenu(null);
        setMenuAnchor(null);
    }, []);
    // Left and Right move between the open menus, as a menu bar does.
    useEffect(() => {
        if (!activeMenu) return;
        const onKey = (event: KeyboardEvent) => {
            if (event.defaultPrevented) return;
            if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
            if (event.target instanceof Element && event.target.closest("input, textarea")) return;
            event.preventDefault();
            const next: MenuKey = activeMenu === "file" ? "view" : "file";
            const button = menuButtons.current.get(next);
            if (button) openDropdown(next, button);
        };
        window.addEventListener("keydown", onKey, true);
        return () => window.removeEventListener("keydown", onKey, true);
    }, [activeMenu, openDropdown]);
    const actions: Record<string, (() => void) | undefined> = {
        new_mentor: onNewMentor,
        new_window: () => { void invoke("open_new_window").catch(() => { }); },
        open_pdf: onOpenPdf,
        open_search: onSearch,
        close_reader: onCloseReader,
        ...(onReaderBack ? { reader_back: onReaderBack } : {}),
        ...(onReaderForward ? { reader_forward: onReaderForward } : {}),
        prev_mentor: onPreviousMentor,
        next_mentor: onNextMentor,
        toggle_library: onToggleLibrary,
        toggle_chat: onToggleChat,
        open_model_picker: () => window.dispatchEvent(new Event("open_model_picker")),
        open_settings: onOpenSettings,
        exit: () => { void invoke("quit_app").catch(() => { }); },
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
        { kind: "item", id: "reader_back", label: "Back", shortcut: shortcut("Reader: Back", `${MOD}[`) },
        { kind: "item", id: "reader_forward", label: "Forward", shortcut: shortcut("Reader: Forward", `${MOD}]`) },
        { kind: "sep" },
        { kind: "item", id: "prev_mentor", label: "Previous Mentor", shortcut: shortcut("Mentor: Previous", `${MOD}${SHIFT}[`) },
        { kind: "item", id: "next_mentor", label: "Next Mentor", shortcut: shortcut("Mentor: Next", `${MOD}${SHIFT}]`) },
        { kind: "sep" },
        { kind: "item", id: "open_settings", label: "Settings…", shortcut: shortcut("App: Settings", `${MOD},`) },
        { kind: "sep" },
        { kind: "item", id: "exit", label: "Exit" },
    ] : [
        { kind: "item", id: "toggle_library", label: "Toggle Library", shortcut: shortcut("App: Toggle Library", `${MOD}B`) },
        { kind: "item", id: "toggle_chat", label: "Toggle Conversation", shortcut: shortcut("App: Toggle Conversation", `${MOD}${SHIFT}B`) },
        { kind: "item", id: "open_model_picker", label: "Switch Model…", shortcut: shortcut("App: Switch Model", `${MOD}.`) },
        { kind: "sep" },
        { kind: "item", id: "zoom_in", label: "Zoom In", shortcut: shortcut("View: Zoom In", `${MOD}+`) },
        { kind: "item", id: "zoom_out", label: "Zoom Out", shortcut: shortcut("View: Zoom Out", `${MOD}-`) },
        { kind: "item", id: "zoom_reset", label: "Reset Zoom", shortcut: shortcut("View: Zoom Reset", `${MOD}0`) },
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
    const onBarKeyDown = (event: ReactKeyboardEvent<HTMLButtonElement>, key: MenuKey) => {
        if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
            event.preventDefault();
            const next: MenuKey = key === "file" ? "view" : "file";
            const button = menuButtons.current.get(next);
            button?.focus();
            if (activeMenu) openDropdown(next, button!);
        }
        else if (event.key === "ArrowDown" || event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            openDropdown(key, event.currentTarget);
        }
    };
    return (<div ref={barRef} role="menubar" aria-label="Application menu"
      style={{ zIndex: LAYER.popover }}
      // Laid over the window so opening it never moves the workspace below.
      className="fixed inset-x-0 top-0 flex h-7 items-center gap-0.5 border-b border-stroke bg-background-base px-2 text-[12px] shadow-md" data-tauri-drag-region="false">
      {MENUS.map(({ key, label }) => {
            const isActive = activeMenu === key;
            return (<button key={key} type="button" role="menuitem" aria-haspopup="menu" aria-expanded={isActive}
              data-tauri-drag-region="false" ref={(element) => { if (element) menuButtons.current.set(key, element); else menuButtons.current.delete(key); }}
              onClick={(e) => {
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
                }} onKeyDown={(event) => onBarKeyDown(event, key)}
              className={`rounded px-2 py-0.5 transition-colors ${isActive
                    ? "bg-selection-hover text-content"
                    : "text-content/70 hover:bg-content/10 hover:text-content"}`}>
            {label}
          </button>);
        })}

      {activeMenu && menuAnchor ? (<ContextMenu key={activeMenu} x={menuAnchor.x} y={menuAnchor.y} items={getMenuItems(activeMenu)} ariaLabel={`${activeMenu} menu`} onPick={handlePick} onClose={() => dismissBar(false)}/>) : null}
    </div>);
}
