mod cursor_store;
use tauri::Manager;

mod account_identity;
mod agent;
mod agent_documents;
mod agent_transcript;
mod canvas;
mod canvas_mcp;
mod chat_background;
mod control;
pub mod control_cli;
mod course;
mod feeds;
mod fs;
mod harness;
mod learning;
mod link_preview;
#[cfg(target_os = "macos")]
mod macos;
mod mcp;
mod menu;
mod notes;
mod notifications;
mod pasteboard;
mod project_logo;
mod rate_limits;
mod reminders;
mod session_store;
mod skills;
#[cfg(target_os = "macos")]
mod trackpad_zoom;
#[cfg(target_os = "windows")]
mod tray;
mod v2ex;
mod window;
#[cfg(windows)]
mod windows;
mod x_feed;

/// Project directory for new sessions — prefer cwd, else home.
#[tauri::command]
fn default_cwd() -> String {
    if let Ok(cwd) = std::env::current_dir() {
        return fs::path_to_js(&cwd);
    }
    dirs_home()
        .map(|home| fs::path_to_js(std::path::Path::new(&home)))
        .unwrap_or_else(|| "~".into())
}

#[tauri::command]
fn home_dir() -> String {
    dirs_home()
        .map(|home| fs::path_to_js(std::path::Path::new(&home)))
        .unwrap_or_else(|| "~".into())
}

pub(crate) struct PasswdIdentity {
    pub home: String,
    pub user: String,
    pub shell: String,
}

pub(crate) fn dirs_home() -> Option<String> {
    #[cfg(windows)]
    let keys = ["USERPROFILE", "HOME"];
    #[cfg(not(windows))]
    let keys = ["HOME", "USERPROFILE"];
    for key in keys {
        if let Some(home) = std::env::var_os(key) {
            let home = home.to_string_lossy().into_owned();
            if !home.is_empty() {
                return Some(home);
            }
        }
    }
    match (std::env::var("HOMEDRIVE"), std::env::var("HOMEPATH")) {
        (Ok(drive), Ok(path)) if !drive.is_empty() && !path.is_empty() => {
            Some(format!("{drive}{path}"))
        }
        _ => passwd_identity().map(|id| id.home),
    }
}

/// Hide the console window that Windows allocates for GUI-spawned children.
pub(crate) fn hide_window_console(cmd: &mut std::process::Command) {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(WINDOWS_BACKGROUND_CREATION_FLAGS);
    }
    let _ = cmd;
}

#[cfg(windows)]
const WINDOWS_BACKGROUND_CREATION_FLAGS: u32 = 0x0800_0000; // CREATE_NO_WINDOW

#[cfg(all(test, windows))]
mod background_command_tests {
    use super::*;

    #[test]
    fn background_commands_keep_piped_output_and_exit_status() {
        assert_eq!(WINDOWS_BACKGROUND_CREATION_FLAGS, 0x0800_0000);

        let mut cmd = std::process::Command::new("cmd.exe");
        cmd.args(["/D", "/C", "(echo stdout)&(echo stderr 1>&2)&exit /b 7"]);
        hide_window_console(&mut cmd);

        let output = cmd.output().expect("background command should run");
        assert_eq!(output.status.code(), Some(7));
        assert!(String::from_utf8_lossy(&output.stdout).contains("stdout"));
        assert!(String::from_utf8_lossy(&output.stderr).contains("stderr"));
    }
}

/// Finder-launched .app bundles often omit HOME/USER/SHELL. Fall back to the
/// passwd database so harness CLIs still find their configuration and the login keychain.
pub(crate) fn passwd_identity() -> Option<PasswdIdentity> {
    #[cfg(unix)]
    {
        let uid = unsafe { libc::getuid() };
        let mut buf = vec![0u8; 4096];
        let mut pwd = unsafe { std::mem::zeroed::<libc::passwd>() };
        let mut result = std::ptr::null_mut::<libc::passwd>();
        let rc = unsafe {
            libc::getpwuid_r(
                uid,
                &mut pwd,
                buf.as_mut_ptr() as *mut libc::c_char,
                buf.len(),
                &mut result,
            )
        };
        if rc != 0 || result.is_null() {
            return None;
        }
        unsafe {
            let user = std::ffi::CStr::from_ptr(pwd.pw_name)
                .to_string_lossy()
                .into_owned();
            let home = std::ffi::CStr::from_ptr(pwd.pw_dir)
                .to_string_lossy()
                .into_owned();
            let shell = std::ffi::CStr::from_ptr(pwd.pw_shell)
                .to_string_lossy()
                .into_owned();
            if user.is_empty() || home.is_empty() {
                return None;
            }
            Some(PasswdIdentity { home, user, shell })
        }
    }
    #[cfg(not(unix))]
    {
        None
    }
}

#[tauri::command]
fn set_traffic_lights_visible(
    #[allow(unused_variables)] window: tauri::WebviewWindow,
    #[allow(unused_variables)] visible: bool,
) {
    #[cfg(target_os = "macos")]
    macos::set_visible(&window, visible);
}

#[tauri::command]
fn set_window_background_blur(
    #[allow(unused_variables)] window: tauri::WebviewWindow,
    #[allow(unused_variables)] radius: u8,
) {
    #[cfg(target_os = "macos")]
    macos::set_background_blur_radius(&window, radius);
}

#[tauri::command]
fn set_dock_badge(
    #[allow(unused_variables)] window: tauri::WebviewWindow,
    #[allow(unused_variables)] count: u32,
) {
    #[cfg(target_os = "macos")]
    macos::set_window_badge(&window, count);
}

#[tauri::command]
fn set_trackpad_zoom_enabled(
    #[allow(unused_variables)] window: tauri::WebviewWindow,
    #[allow(unused_variables)] enabled: bool,
) {
    #[cfg(target_os = "macos")]
    trackpad_zoom::set_enabled(&window, enabled);
}

#[tauri::command]
fn open_new_window(app: tauri::AppHandle) -> Result<(), String> {
    window::open_new_window(&app)
}

fn should_request_quit(code: Option<i32>) -> bool {
    code.is_some() || cfg!(any(target_os = "linux", target_os = "windows"))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    #[cfg(windows)]
    windows::initialize().expect("Failed to initialize Windows process safety");
    let app = tauri::Builder::default()
        .register_uri_scheme_protocol("loci-widget", |_context, request| {
            learning::widget_proxy_response(request.uri().path())
        })
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .manage(harness::HarnessHost::new())
        .manage(x_feed::XFeedState::default())
        .setup(|app| {
            harness::reap_orphaned_harness_processes();
            session_store::init(app.handle())?;
            control::init(app.handle())?;
            reminders::init(app.handle());
            menu::install(app.handle())?;
            #[cfg(target_os = "windows")]
            tray::install(app.handle())?;
            #[cfg(target_os = "macos")]
            {
                macos::install_dock_menu(app.handle());
                if let Some(window) = app.get_webview_window("main") {
                    macos::install(&window);
                }
            }
            #[cfg(not(target_os = "macos"))]
            {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.set_decorations(false);
                    let _ = window.set_shadow(true);
                }
            }
            Ok(())
        })
        .on_menu_event(|app, event| {
            menu::dispatch(app, event.id().as_ref());
        })
        .invoke_handler(tauri::generate_handler![
            learning::learning_source_register,
            learning::learning_source_get,
            learning::learning_document_register,
            learning::learning_document_get,
            learning::learning_document_find,
            learning::learning_document_relocate,
            learning::learning_annotations_list,
            learning::learning_annotation_upsert,
            learning::learning_annotation_delete,
            learning::learning_annotation_link,
            learning::learning_widget_upsert,
            learning::learning_widget_get,
            learning::learning_widgets_list,
            learning::learning_widget_save,
            learning::learning_widget_state,
            learning::learning_widgets_delete_owner,
            account_identity::provider_account_identity,
            chat_background::save_chat_background,
            chat_background::remove_chat_background,
            chat_background::save_project_chat_background,
            chat_background::remove_project_chat_background,
            chat_background::download_wallpaper,
            control::control_authorize_turn,
            control::control_turn_finished,
            control::app_cli_path,
            control::control_reply,
            fs::resolve_project_location,
            fs::claude_shell_commands,
            fs::create_path,
            fs::inspect_paths,
            fs::read_file_base64,
            fs::read_binary_file,
            fs::read_document_file,
            fs::write_attachment,
            fs::save_generated_image,
            fs::delete_generated_images,
            fs::read_text_file,
            fs::write_text_file,
            fs::delete_path,
            fs::list_dir,
            fs::list_project_files,
            fs::stat_files,
            fs::rename_path,
            fs::trash_path,
            fs::copy_path,
            fs::move_path,
            fs::reveal_path,
            fs::open_path_with_default_app,
            cursor_store::cursor_tool_calls,
            cursor_store::cursor_subagent_runs,
            harness::harness_resolve_cursor,
            harness::harness_resolve_grok,
            harness::harness_resolve_opencode,
            harness::harness_resolve_pi,
            harness::harness_resolve_omp,
            harness::harness_resolve_fx,
            harness::harness_resolve_hermes,
            harness::harness_resolve_antigravity,
            harness::harness_free_port,
            harness::harness_http,
            harness::harness_sse_open,
            harness::harness_sse_close,
            harness::harness_resolve_codex,
            harness::harness_resolve_configured,
            harness::harness_runtime_binary_paths,
            harness::harness_resolve_claude,
            harness::claude_mcp_list,
            harness::claude_mcp_add,
            harness::claude_mcp_remove,
            harness::mcp_provider_login,
            harness::harness_spawn,
            harness::provider_account_remove,
            harness::harness_write,
            harness::harness_kill,
            harness::harness_kill_all,
            harness::harness_exec,
            link_preview::fetch_link_preview,
            feeds::feeds_state_list,
            feeds::feeds_mark_seen,
            feeds::feeds_mark_seen_many,
            feeds::feeds_set_starred,
            v2ex::v2ex_status,
            v2ex::v2ex_set_token,
            v2ex::v2ex_clear_token,
            v2ex::v2ex_topics,
            v2ex::v2ex_topic,
            v2ex::v2ex_replies,
            v2ex::v2ex_node,
            v2ex::v2ex_notifications,
            x_feed::x_feed_show,
            x_feed::x_feed_set_bounds,
            x_feed::x_feed_hide,
            x_feed::x_feed_navigate,
            x_feed::x_feed_action,
            x_feed::x_feed_capture,
            mcp::mcp_add,
            mcp::mcp_discover,
            #[cfg(target_os = "macos")]
            menu::keybindings_set_overrides,
            canvas::canvas_list,
            canvas::canvas_get,
            canvas::canvas_upsert,
            canvas::canvas_delete,
            canvas::canvas_checkpoint_canvas,
            canvas::canvas_checkpoint_latest,
            course::course_list,
            course::course_get,
            course::course_upsert,
            course::course_progress_get,
            course::course_progress_set,
            canvas_mcp::canvas_mcp_server,
            agent::agent_load,
            agent::agent_read,
            agent::agent_save,
            agent_documents::agent_documents_list,
            agent_documents::agent_documents_get,
            agent_documents::agent_documents_upsert,
            agent_documents::agent_documents_import,
            agent_documents::agent_documents_delete,
            agent_transcript::agent_transcript_append,
            agent_transcript::agent_transcript_page,
            agent_transcript::agent_transcript_clear,
            notes::notes_list,
            notes::notes_get,
            notes::notes_upsert,
            notes::notes_finalize_slug,
            notes::notes_delete,
            notes::notes_save_image,
            notes::notes_image_path,
            notifications::notification_permission,
            notifications::request_notification_permission,
            notifications::show_notification,
            notifications::open_notification_settings,
            pasteboard::clipboard_file_paths,
            pasteboard::copy_file_to_clipboard,
            pasteboard::clipboard_image,
            project_logo::save_project_logo,
            project_logo::forget_logo_file,
            project_logo::remove_project_logo,
            rate_limits::fetch_claude_usage,
            reminders::reminder_list,
            reminders::reminder_set,
            reminders::reminder_clear,
            reminders::reminder_configure,
            reminders::reminder_register_window,
            reminders::reminder_open,
            reminders::reminder_take_open,
            session_store::session_upsert,
            session_store::session_list_by_project,
            session_store::session_rebase_project,
            session_store::session_get,
            session_store::session_search,
            session_store::cancel_session_search,
            session_store::session_delete,
            session_store::session_set_archived,
            session_store::session_set_pinned,
            session_store::session_set_in_flight,
            session_store::session_list_in_flight,
            session_store::session_take_in_flight,
            session_store::workspace_set_snapshot,
            session_store::workspace_get_snapshot,
            skills::list_skills,
            window::set_window_glass_enabled,
            window::hide_window,
            window::destroy_window,
            window::quit_poll_reply,
            window::quit_decision,
            window::quit_ready,
            default_cwd,
            home_dir,
            set_traffic_lights_visible,
            set_window_background_blur,
            set_dock_badge,
            set_trackpad_zoom_enabled,
            open_new_window,
        ])
        .build(tauri::generate_context!())
        .expect("error while building Loci");

    app.run(|handle, event| match event {
        #[cfg(target_os = "macos")]
        tauri::RunEvent::Reopen {
            has_visible_windows: false,
            ..
        } => {
            let _ = window::show_hidden_or_open_new(handle);
        }
        tauri::RunEvent::Ready => {
            #[cfg(target_os = "macos")]
            {
                macos::request_badge_authorization();
                notifications::install_delegate(handle);
                #[cfg(debug_assertions)]
                macos::prefer_bundle_dock_icon();
            }
            window::ensure_launch_window_visible(handle);
        }
        tauri::RunEvent::WindowEvent {
            label,
            event: tauri::WindowEvent::Destroyed,
            ..
        } => {
            #[cfg(target_os = "macos")]
            trackpad_zoom::forget_window(&label);
            window::forget_quit_window(handle, &label);
            let other_window = window::workspace_windows(handle)
                .iter()
                .any(|window| window.label() != label);
            control::window_closed(handle, &label);
            if !other_window {
                reap_harness_children(handle);
            }
        }
        tauri::RunEvent::ExitRequested { api, code, .. } => {
            if window::allow_exit() {
                return;
            }
            api.prevent_exit();
            // Last window destroyed (red button). Stay in the dock on macOS;
            // ⌘Q is a separate menu handler and arrives with an exit code.
            // Linux and Windows have no dock, so the last close is a quit.
            if !should_request_quit(code) {
                return;
            }
            window::request_quit(handle);
        }
        tauri::RunEvent::Exit => {
            reap_harness_children(handle);
        }
        _ => {}
    });
}

fn reap_harness_children(handle: &tauri::AppHandle) {
    if let Some(host) = handle.try_state::<harness::HarnessHost>() {
        host.kill_all();
    }
}

#[cfg(all(debug_assertions, target_os = "macos"))]
pub fn ensure_macos_dev_bundle() {
    macos::ensure_dev_bundle();
}

#[cfg(test)]
mod tests {
    use super::should_request_quit;

    #[test]
    fn explicit_exit_requests_quit() {
        assert!(should_request_quit(Some(0)));
    }

    #[cfg(any(target_os = "linux", target_os = "windows"))]
    #[test]
    fn last_window_close_requests_quit_without_dock() {
        assert!(should_request_quit(None));
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn last_window_close_stays_alive_with_dock() {
        assert!(!should_request_quit(None));
    }
}
