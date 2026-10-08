//! How to start Loci's built-in MCP servers with a local JavaScript runtime:
//! the official Excalidraw server bundle behind Loci's store bridge, and the
//! learning server that reaches a project's learning map.
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;

use serde::Serialize;
use tauri::path::BaseDirectory;
use tauri::{AppHandle, Manager};

const BRIDGE: &str = "resources/excalidraw-mcp/loci-bridge.mjs";
const LEARN_SERVER: &str = "resources/learn-mcp/loci-learn.mjs";

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct CanvasMcpServer {
    pub command: String,
    pub args: Vec<String>,
}

// A missing runtime is looked up again, so installing Node needs no restart.
static RESOLVED: Mutex<Option<CanvasMcpServer>> = Mutex::new(None);
static LEARN_RESOLVED: Mutex<Option<CanvasMcpServer>> = Mutex::new(None);

/// The stdio command agent CLIs should run, or why drawing tools are unavailable.
#[tauri::command(async)]
pub fn canvas_mcp_server(app: AppHandle) -> Result<CanvasMcpServer, String> {
    if let Some(server) = RESOLVED.lock().ok().and_then(|cached| cached.clone()) {
        return Ok(server);
    }
    let bridge = resource_path(&app, BRIDGE)
        .ok_or_else(|| "Loci's Excalidraw MCP files are missing from this build.".to_string())?;
    let runtime = runtime()?;
    let server = CanvasMcpServer {
        command: plain_path(&runtime),
        args: vec![plain_path(&bridge)],
    };
    if let Ok(mut cached) = RESOLVED.lock() {
        *cached = Some(server.clone());
    }
    Ok(server)
}

/// The stdio command for the learning MCP server, or why it is unavailable.
#[tauri::command(async)]
pub fn learn_mcp_server(app: AppHandle) -> Result<CanvasMcpServer, String> {
    if let Some(server) = LEARN_RESOLVED.lock().ok().and_then(|cached| cached.clone()) {
        return Ok(server);
    }
    let script = resource_path(&app, LEARN_SERVER)
        .ok_or_else(|| "Loci's learning MCP files are missing from this build.".to_string())?;
    let runtime = runtime().map_err(|_| {
        "The learning map needs Node.js 20.11 or newer (or Bun) on your PATH.".to_string()
    })?;
    let server = CanvasMcpServer {
        command: plain_path(&runtime),
        args: vec![plain_path(&script)],
    };
    if let Ok(mut cached) = LEARN_RESOLVED.lock() {
        *cached = Some(server.clone());
    }
    Ok(server)
}

fn resource_path(app: &AppHandle, relative: &str) -> Option<PathBuf> {
    let bundled = app
        .path()
        .resolve(relative, BaseDirectory::Resource)
        .ok()
        .filter(|path| path.is_file());
    // `cargo run` without the Tauri CLI does not stage resources.
    #[cfg(debug_assertions)]
    let bundled = bundled.or_else(|| {
        let source = Path::new(env!("CARGO_MANIFEST_DIR")).join(relative);
        source.is_file().then_some(source)
    });
    bundled
}

fn runtime() -> Result<PathBuf, String> {
    if let Some(node) = crate::harness::which_via_login_shell("node") {
        let version = crate::harness::exec_output(
            &node.to_string_lossy(),
            &["--version".to_string()],
            None,
            Duration::from_secs(10),
        )
        .map(|output| String::from_utf8_lossy(&output.stdout).into_owned())
        .unwrap_or_default();
        if node_runs_bridge(&version) {
            return Ok(node);
        }
    }
    crate::harness::which_via_login_shell("bun").ok_or_else(|| {
        "Excalidraw drawing tools need Node.js 20.11 or newer (or Bun) on your PATH.".to_string()
    })
}

/// The official bundle reads `import.meta.dirname`, which Node added in 20.11.
fn node_runs_bridge(version: &str) -> bool {
    let mut parts = version.trim().trim_start_matches('v').split('.');
    let mut number = || parts.next().and_then(|part| part.parse::<u32>().ok());
    match (number(), number()) {
        (Some(major), Some(minor)) => major > 20 || (major == 20 && minor >= 11),
        _ => false,
    }
}

/// Windows resolves resources to `\\?\C:\…`, which Node cannot import from.
fn plain_path(path: &Path) -> String {
    let text = path.to_string_lossy();
    match text.strip_prefix(r"\\?\") {
        Some(rest) if !rest.starts_with("UNC\\") => rest.to_string(),
        _ => text.into_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_only_node_versions_that_can_load_the_official_bundle() {
        for version in ["v20.11.0\n", "v20.19.4", "v22.0.0", "24.21.0"] {
            assert!(node_runs_bridge(version), "{version}");
        }
        for version in ["v20.10.0", "v18.20.4", "v19.9.0", "", "node", "v20"] {
            assert!(!node_runs_bridge(version), "{version}");
        }
    }

    #[test]
    fn strips_only_the_verbatim_drive_prefix() {
        assert_eq!(
            plain_path(Path::new(r"\\?\C:\Loci\bridge.mjs")),
            r"C:\Loci\bridge.mjs"
        );
        assert_eq!(
            plain_path(Path::new(r"\\?\UNC\server\share\bridge.mjs")),
            r"\\?\UNC\server\share\bridge.mjs"
        );
        assert_eq!(
            plain_path(Path::new("/opt/Loci/bridge.mjs")),
            "/opt/Loci/bridge.mjs"
        );
    }

    #[test]
    fn the_vendored_official_server_and_bridge_ship_with_the_app() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("resources/excalidraw-mcp");
        for file in [
            "loci-bridge.mjs",
            "element-properties.mjs",
            "official/server.js",
            "official/mcp-app.html",
            "official/manifest.json",
            "SOURCE",
        ] {
            assert!(root.join(file).is_file(), "missing {file}");
        }
        let config =
            std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("tauri.conf.json"))
                .unwrap();
        let config: serde_json::Value = serde_json::from_str(&config).unwrap();
        let resources = config["bundle"]["resources"].as_array().unwrap();
        assert!(resources
            .iter()
            .any(|entry| entry.as_str() == Some("resources/excalidraw-mcp/**/*")));
    }

    #[test]
    fn the_learning_server_ships_with_the_app() {
        let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
        assert!(manifest.join(LEARN_SERVER).is_file());
        let config = std::fs::read_to_string(manifest.join("tauri.conf.json")).unwrap();
        let config: serde_json::Value = serde_json::from_str(&config).unwrap();
        let resources = config["bundle"]["resources"].as_array().unwrap();
        assert!(resources
            .iter()
            .any(|entry| entry.as_str() == Some("resources/learn-mcp/**/*")));
    }
}
