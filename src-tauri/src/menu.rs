#[cfg(target_os = "macos")]
use serde::Deserialize;
#[cfg(target_os = "macos")]
use std::collections::HashMap;
#[cfg(target_os = "macos")]
use tauri::menu::{AboutMetadata, Menu, MenuItem, MenuItemBuilder, SubmenuBuilder};
#[cfg(target_os = "macos")]
use tauri::Wry;
use tauri::{AppHandle, Emitter};

#[cfg(target_os = "macos")]
#[derive(Deserialize)]
pub struct KeybindingOverride {
    disabled: Option<bool>,
    shortcut: Option<String>,
}

#[cfg_attr(not(target_os = "macos"), allow(dead_code))]
fn custom_accelerator(shortcut: &str) -> String {
    let mut parts = shortcut.split('+');
    let key = parts.next_back().unwrap_or_default();
    let key = match key {
        value if value.starts_with("Key") => &value[3..],
        value if value.starts_with("Digit") => &value[5..],
        "Equal" => "=",
        "Minus" => "-",
        "Backquote" => "`",
        "BracketLeft" => "[",
        "BracketRight" => "]",
        "Backslash" => "\\",
        "ArrowUp" => "Up",
        "ArrowDown" => "Down",
        "ArrowLeft" => "Left",
        "ArrowRight" => "Right",
        other => other,
    };
    parts
        .map(|part| match part {
            "Command" => "Cmd",
            "Control" => "Ctrl",
            "Option" => "Option",
            "Shift" => "Shift",
            other => other,
        })
        .chain(std::iter::once(key))
        .collect::<Vec<_>>()
        .join("+")
}

pub fn install(app: &AppHandle) -> tauri::Result<()> {
    #[cfg(target_os = "macos")]
    app.set_menu(build(app, &HashMap::new())?)?;
    let _ = app;
    Ok(())
}

/// Exit from the in-app menu bar where the system has none, through the same
/// unsaved-work check as the window's own close.
#[tauri::command]
pub fn quit_app(app: AppHandle) {
    crate::window::request_quit(&app);
}

#[cfg(target_os = "macos")]
#[tauri::command]
pub fn keybindings_set_overrides(
    app: AppHandle,
    overrides: HashMap<String, KeybindingOverride>,
) -> Result<(), String> {
    let menu = build(&app, &overrides).map_err(|error| error.to_string())?;
    // set_menu hands back the previous menu; this command only needs to know
    // whether it succeeded.
    app.set_menu(menu)
        .map(|_| ())
        .map_err(|error| error.to_string())
}

#[cfg(target_os = "macos")]
fn menu_item(
    app: &AppHandle,
    id: &str,
    text: &str,
    accelerator: &str,
    command: &str,
    overrides: &HashMap<String, KeybindingOverride>,
) -> tauri::Result<MenuItem<Wry>> {
    let builder = MenuItemBuilder::with_id(id, text);
    let override_ = overrides.get(command);
    let builder = if override_.and_then(|value| value.disabled).unwrap_or(false) {
        builder
    } else if let Some(shortcut) = override_.and_then(|value| value.shortcut.as_deref()) {
        builder.accelerator(custom_accelerator(shortcut))
    } else {
        builder.accelerator(accelerator)
    };
    builder.build(app)
}

pub fn dispatch(app: &AppHandle, id: &str) {
    match id {
        "new_window" => {
            let _ = crate::window::open_new_window(app);
        }
        "quit" => crate::window::request_quit(app),
        "sidebar_opacity" | "open_search" | "open_model_picker" | "open_settings" => {
            let _ = app.emit(id, ());
        }
        // Window actions target one window: a broadcast would make every
        // window act on a single menu click.
        "new_mentor" | "close_reader" | "prev_mentor" | "next_mentor" | "toggle_library"
        | "toggle_chat" | "zoom_in" | "zoom_out" | "zoom_reset" | "reload" | "open_pdf" => {
            emit_to_focused(app, id)
        }
        _ => {}
    }
}

/// Emit `id` to the focused window, falling back to a visible one, then any.
fn emit_to_focused(app: &AppHandle, id: &str) {
    let windows = crate::window::workspace_windows(app);
    let target = windows
        .iter()
        .find(|window| window.is_focused().unwrap_or(false))
        .or_else(|| {
            windows
                .iter()
                .find(|window| window.is_visible().unwrap_or(false))
        })
        .or(windows.first());
    match target {
        Some(window) => {
            let _ = app.emit_to(window.label(), id, ());
        }
        None => {
            let _ = app.emit(id, ());
        }
    }
}

#[cfg(target_os = "macos")]
fn build(
    app: &AppHandle,
    overrides: &HashMap<String, KeybindingOverride>,
) -> tauri::Result<Menu<Wry>> {
    let open_settings = menu_item(
        app,
        "open_settings",
        "Settings…",
        "CmdOrCtrl+,",
        "App: Settings",
        overrides,
    )?;
    let new_window = menu_item(
        app,
        "new_window",
        "New Window",
        "CmdOrCtrl+Shift+N",
        "App: New Window",
        overrides,
    )?;
    let new_mentor = menu_item(
        app,
        "new_mentor",
        "New Mentor…",
        "CmdOrCtrl+T",
        "Mentor: New",
        overrides,
    )?;
    let open_pdf = MenuItemBuilder::with_id("open_pdf", "Open PDF…").build(app)?;
    let open_search = menu_item(
        app,
        "open_search",
        "Search…",
        "CmdOrCtrl+K",
        "App: Search",
        overrides,
    )?;
    let close_reader = menu_item(
        app,
        "close_reader",
        "Close",
        "CmdOrCtrl+W",
        "Reader: Close",
        overrides,
    )?;
    let prev_mentor = menu_item(
        app,
        "prev_mentor",
        "Previous Mentor",
        "CmdOrCtrl+Shift+[",
        "Mentor: Previous",
        overrides,
    )?;
    let next_mentor = menu_item(
        app,
        "next_mentor",
        "Next Mentor",
        "CmdOrCtrl+Shift+]",
        "Mentor: Next",
        overrides,
    )?;
    let toggle_library = menu_item(
        app,
        "toggle_library",
        "Toggle Library",
        "CmdOrCtrl+B",
        "App: Toggle Library",
        overrides,
    )?;
    let toggle_chat = menu_item(
        app,
        "toggle_chat",
        "Toggle Conversation",
        "CmdOrCtrl+Shift+B",
        "App: Toggle Conversation",
        overrides,
    )?;
    let open_model_picker = menu_item(
        app,
        "open_model_picker",
        "Switch Model…",
        "CmdOrCtrl+.",
        "App: Switch Model",
        overrides,
    )?;
    let sidebar_opacity =
        MenuItemBuilder::with_id("sidebar_opacity", "Sidebar Appearance…").build(app)?;
    // No accelerators here on purpose: the webview key handler owns
    // CmdOrCtrl + - 0, and a menu accelerator would fire the same command
    // a second time on top of it.
    let zoom_in = MenuItemBuilder::with_id("zoom_in", "Zoom In").build(app)?;
    let zoom_out = MenuItemBuilder::with_id("zoom_out", "Zoom Out").build(app)?;
    let zoom_reset = MenuItemBuilder::with_id("zoom_reset", "Reset Zoom").build(app)?;
    let reload = menu_item(
        app,
        "reload",
        "Reload",
        "CmdOrCtrl+Shift+R",
        "View: Reload",
        overrides,
    )?;

    let file = SubmenuBuilder::with_id(app, "file", "File")
        .item(&new_window)
        .item(&new_mentor)
        .item(&open_pdf)
        .item(&open_search)
        .separator()
        .item(&close_reader)
        .separator()
        .item(&prev_mentor)
        .item(&next_mentor)
        .build()?;

    let view = SubmenuBuilder::new(app, "View")
        .item(&toggle_library)
        .item(&toggle_chat)
        .item(&open_model_picker)
        .separator()
        .item(&zoom_in)
        .item(&zoom_out)
        .item(&zoom_reset)
        .item(&reload)
        .separator()
        .item(&sidebar_opacity)
        .build()?;

    let edit = SubmenuBuilder::new(app, "Edit")
        .undo()
        .redo()
        .separator()
        .cut()
        .copy()
        .paste()
        .select_all()
        .separator()
        .build()?;

    #[cfg(target_os = "macos")]
    {
        let quit = MenuItemBuilder::with_id("quit", "Quit Loci")
            .accelerator("CmdOrCtrl+Q")
            .build(app)?;
        let app_menu = SubmenuBuilder::new(app, "Loci")
            .about(Some(AboutMetadata::default()))
            .separator()
            .item(&open_settings)
            .separator()
            .hide()
            .hide_others()
            .show_all()
            .separator()
            .item(&quit)
            .build()?;
        // Tauri registers this submenu via NSApp.setWindowsMenu:, which throws
        // on macOS 12 when the menu is empty and aborts the app at launch.
        let window_menu = SubmenuBuilder::with_id(app, tauri::menu::WINDOW_SUBMENU_ID, "Window")
            .minimize()
            .maximize()
            .build()?;
        return Menu::with_items(app, &[&app_menu, &file, &edit, &view, &window_menu]);
    }

    #[allow(unreachable_code)]
    Menu::with_items(app, &[&file, &edit, &view])
}
