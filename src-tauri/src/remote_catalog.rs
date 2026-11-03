//! What a connected device may do with each registered command. Remote access
//! builds its allow list from this table, so a command left out of it is never
//! reachable from another device; the test below fails until every command
//! registered in `lib.rs` has a class.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CommandClass {
    /// Forwarded to the host; reads host data only.
    Read,
    /// Forwarded to the host; changes host data.
    Write,
    /// Changes a session, which only the host window's session driver may do.
    SessionAction,
    /// Forwarded and carried out on the host machine (Finder, host browser).
    OnHost,
    /// Run by the client against its own machine, never forwarded.
    ClientLocal,
    /// Refused for every connected device.
    Never,
}

use CommandClass::*;

const CATALOG: &[(&str, CommandClass)] = &[
    // reset
    ("workspace_reset", Never),
    ("workspace_reset_status", Never),
    ("workspace_reset_ready", Never),
    ("workspace_reset_cleaned", Never),
    ("workspace_reset_request_finished", Never),
    // learning
    ("learning_source_register", Write),
    ("learning_source_get", Read),
    ("learning_document_register", Write),
    ("learning_document_get", Read),
    ("learning_document_find", Read),
    ("learning_document_relocate", Write),
    ("learning_annotations_list", Read),
    ("learning_annotations_for", Read),
    ("learning_annotations_query", Read),
    ("learning_annotation_get", Read),
    ("learning_annotation_upsert", Write),
    ("learning_annotation_delete", Write),
    ("learning_annotation_link", Write),
    // chat_background: appearance belongs to the device showing it
    ("save_chat_background", ClientLocal),
    ("remove_chat_background", ClientLocal),
    ("download_wallpaper", ClientLocal),
    // control
    ("control_authorize_turn", Never),
    ("control_turn_finished", Never),
    ("app_cli_path", Read),
    ("control_reply", Never),
    ("control_window_ready", Never),
    ("cli_access_status", Read),
    ("cli_access_set", Write),
    ("cli_access_rotate", Write),
    ("cli_install", OnHost),
    // fs
    ("resolve_project_location", Read),
    ("claude_shell_commands", Read),
    ("create_path", Write),
    ("inspect_paths", Read),
    ("read_file_base64", Read),
    ("read_binary_file", Read),
    ("read_document_file", Read),
    ("write_attachment", Write),
    ("save_generated_image", Write),
    ("delete_generated_images", Write),
    ("read_text_file", Read),
    ("write_text_file", Write),
    ("delete_path", Write),
    ("list_dir", Read),
    ("list_project_files", Read),
    ("stat_files", Read),
    ("rename_path", Write),
    ("trash_path", Write),
    ("copy_path", Write),
    ("move_path", Write),
    ("reveal_path", OnHost),
    ("open_path_with_default_app", OnHost),
    // cursor_store
    ("cursor_tool_calls", Read),
    ("cursor_subagent_runs", Read),
    // harness: the CLI driver runs only in the host window
    ("harness_resolve_cursor", Never),
    ("harness_resolve_grok", Never),
    ("harness_resolve_opencode", Never),
    ("harness_resolve_pi", Never),
    ("harness_resolve_omp", Never),
    ("harness_resolve_fx", Never),
    ("harness_resolve_hermes", Never),
    ("harness_resolve_antigravity", Never),
    ("harness_free_port", Never),
    ("harness_http", Never),
    ("harness_sse_open", Never),
    ("harness_sse_close", Never),
    ("harness_resolve_codex", Never),
    ("harness_resolve_configured", Never),
    ("harness_runtime_binary_paths", Never),
    ("harness_resolve_claude", Never),
    ("claude_mcp_list", Read),
    ("claude_mcp_add", Write),
    ("claude_mcp_remove", Write),
    ("mcp_provider_login", OnHost),
    ("harness_spawn", Never),
    ("harness_write", Never),
    ("harness_kill", Never),
    ("harness_kill_all", Never),
    ("harness_exec", Never),
    ("fetch_link_preview", ClientLocal),
    // mcp
    ("mcp_add", Write),
    ("mcp_discover", Read),
    ("keybindings_set_overrides", ClientLocal),
    // canvas
    ("canvas_list", Read),
    ("canvas_get", Read),
    ("canvas_upsert", Write),
    ("canvas_delete", Write),
    ("canvas_checkpoint_canvas", Write),
    ("canvas_checkpoint_latest", Read),
    // course
    ("course_list", Read),
    ("course_list_all", Read),
    ("course_delete", Write),
    ("course_get", Read),
    ("course_upsert", Write),
    ("course_progress_get", Read),
    ("course_progress_set", Write),
    ("canvas_mcp_server", Never),
    // agent
    ("agent_load", Read),
    ("agent_read", Read),
    ("agent_save", Write),
    ("agent_workdir_create", Write),
    ("agent_workdir_ensure", Write),
    ("course_path_read", Read),
    ("course_path_write", Write),
    // code
    ("code_read", Read),
    ("code_pin_status", Read),
    ("code_resolve", Read),
    ("code_symbols", Read),
    ("code_definition", Read),
    ("code_references", Read),
    // mentor_store
    ("mentors_load", Read),
    ("mentors_sync", Write),
    ("mentors_remove", Write),
    ("storage_status", Read),
    ("storage_migrate", Write),
    ("storage_reindex", Write),
    ("library_check", Read),
    ("library_search", Read),
    ("mentor_state_all", Read),
    ("mentor_state_set", Write),
    ("mentors_export", Write),
    ("mentors_import", Write),
    // agent_documents
    ("agent_documents_list", Read),
    ("agent_documents_get", Read),
    ("agent_documents_upsert", Write),
    ("agent_documents_import", Write),
    ("agent_documents_write_guide", Write),
    ("source_translation_read", Read),
    ("source_translation_write", Write),
    ("agent_documents_delete", Write),
    // agent_transcript
    ("agent_transcript_append", SessionAction),
    ("agent_transcript_page", Read),
    ("agent_transcript_clear", SessionAction),
    // notes
    ("notes_list", Read),
    ("notes_get", Read),
    ("notes_upsert", Write),
    ("notes_finalize_slug", Write),
    ("notes_delete", Write),
    ("notes_save_image", Write),
    ("notes_image_path", Read),
    // notifications
    ("notification_permission", ClientLocal),
    ("request_notification_permission", ClientLocal),
    ("show_notification", OnHost),
    ("open_notification_settings", ClientLocal),
    // pasteboard
    ("clipboard_file_paths", ClientLocal),
    // Puts a file on the clipboard by path: the path is the host's, the
    // clipboard the client's, so neither side can run it as is.
    ("copy_file_to_clipboard", Never),
    ("clipboard_image", ClientLocal),
    // session_store
    ("session_upsert", SessionAction),
    ("session_list_by_project", Read),
    ("session_rebase_project", SessionAction),
    ("session_get", Read),
    ("session_search", Read),
    ("cancel_session_search", Read),
    ("session_delete", SessionAction),
    ("session_set_archived", SessionAction),
    ("session_set_pinned", SessionAction),
    ("session_set_in_flight", SessionAction),
    ("session_list_in_flight", Read),
    ("session_take_in_flight", SessionAction),
    // The window layout snapshot is per window; whether a client keeps its own
    // or shares the host's is not decided yet.
    ("workspace_set_snapshot", Never),
    ("workspace_get_snapshot", Never),
    ("list_skills", Read),
    // window
    ("set_window_glass_enabled", ClientLocal),
    ("hide_window", ClientLocal),
    ("destroy_window", ClientLocal),
    ("quit_poll_reply", ClientLocal),
    ("quit_decision", ClientLocal),
    ("quit_ready", ClientLocal),
    ("quit_app", ClientLocal),
    // lib
    ("default_cwd", Read),
    ("home_dir", Read),
    ("set_traffic_lights_visible", ClientLocal),
    ("set_window_background_blur", ClientLocal),
    ("set_dock_badge", ClientLocal),
    ("set_trackpad_zoom_enabled", ClientLocal),
    ("open_new_window", ClientLocal),
    // remote: between the host window and the gateway
    ("remote_status", Never),
    ("remote_session_publish", Never),
    ("remote_intent_reply", Never),
    // remote client: this device connecting to another
    ("remote_client_connect", ClientLocal),
    ("remote_client_call", ClientLocal),
    ("remote_client_subscribe", ClientLocal),
    ("remote_client_disconnect", ClientLocal),
    ("remote_client_upload", ClientLocal),
    ("remote_client_cache_put", ClientLocal),
    ("remote_client_cache_get", ClientLocal),
    // remote setup: this device's settings and device group
    ("remote_group_status", ClientLocal),
    ("remote_group_create", ClientLocal),
    ("remote_group_join", ClientLocal),
    ("remote_group_leave", ClientLocal),
    ("remote_devices_list", ClientLocal),
    ("remote_device_remove", ClientLocal),
    ("remote_settings_get", ClientLocal),
    ("remote_settings_set", ClientLocal),
];

pub fn class_of(name: &str) -> Option<CommandClass> {
    CATALOG
        .iter()
        .find(|(command, _)| *command == name)
        .map(|(_, class)| *class)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    /// Command names in `generate_handler!`, read from the source so a command
    /// registered on only one platform still counts.
    fn registered() -> BTreeSet<&'static str> {
        let source = include_str!("lib.rs");
        let start = source
            .find("generate_handler![")
            .expect("generate_handler!")
            + 18;
        source[start..]
            .lines()
            .map(str::trim)
            .take_while(|line| !line.starts_with(']'))
            .filter(|line| !line.is_empty() && !line.starts_with("#["))
            .map(|line| line.trim_end_matches(',').rsplit("::").next().unwrap())
            .collect()
    }

    #[test]
    fn every_registered_command_has_one_class() {
        let registered = registered();
        assert!(
            registered.len() > 100,
            "parsed {} commands",
            registered.len()
        );
        let catalog: BTreeSet<_> = CATALOG.iter().map(|(name, _)| *name).collect();
        assert_eq!(catalog.len(), CATALOG.len(), "a command is listed twice");
        let unclassified: Vec<_> = registered.difference(&catalog).collect();
        assert!(unclassified.is_empty(), "no class for {unclassified:?}");
        let unknown: Vec<_> = catalog.difference(&registered).collect();
        assert!(unknown.is_empty(), "not registered: {unknown:?}");
    }

    #[test]
    fn looks_up_a_class_by_name() {
        assert_eq!(class_of("notes_get"), Some(Read));
        assert_eq!(class_of("harness_spawn"), Some(Never));
        assert_eq!(class_of("no_such_command"), None);
    }
}
