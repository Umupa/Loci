use std::path::{Path, PathBuf};

use serde::Serialize;
use serde_json::Value;
use tauri::State;

use crate::dirs_home;
use crate::fs::expand_home;

fn server_from_json(provider: &str, name: &str, config: &str) -> Result<(String, Value), String> {
    if !matches!(provider, "claude" | "codex") {
        return Err("Unsupported MCP provider".into());
    }
    let value: Value = serde_json::from_str(config).map_err(|e| format!("Invalid JSON: {e}"))?;
    let (name, server) = if let Some(servers) = value.get("mcpServers") {
        let servers = servers.as_object().ok_or("mcpServers must be an object")?;
        if servers.len() != 1 {
            return Err("Add one server at a time".into());
        }
        let (server_name, server) = servers.iter().next().unwrap();
        if !name.trim().is_empty() && name.trim() != server_name {
            return Err("Name does not match the mcpServers entry".into());
        }
        (server_name.clone(), server.clone())
    } else {
        (name.trim().to_owned(), value)
    };
    if name.is_empty() || name.chars().any(char::is_control) {
        return Err("Server name cannot be empty or contain control characters".into());
    }
    if !name
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
    {
        return Err("Server name must use letters, numbers, hyphens, or underscores".into());
    }
    if !server.is_object() {
        return Err("Server configuration must be an object".into());
    }
    let command = server
        .get("command")
        .and_then(Value::as_str)
        .is_some_and(|s| !s.is_empty());
    let url = server
        .get("url")
        .and_then(Value::as_str)
        .is_some_and(|s| !s.is_empty());
    if command == url {
        return Err("Server needs either a command or a URL".into());
    }
    Ok((name, server))
}
#[tauri::command]
pub async fn mcp_add(
    host: State<'_, crate::harness::HarnessHost>,
    cwd: String,
    provider: String,
    scope: String,
    name: String,
    config: String,
) -> Result<(), String> {
    let (name, server) = server_from_json(&provider, &name, &config)?;
    let binary_path = host.runtime_binary_path(&provider);
    tauri::async_runtime::spawn_blocking(move || {
        let project = expand_home(&cwd);
        if !project.is_dir() {
            return Err("Project directory does not exist".into());
        }
        crate::harness::add_mcp_via_cli(
            &provider,
            &scope,
            &cwd,
            &name,
            &server,
            binary_path.as_deref(),
        )
    })
    .await
    .map_err(|e| e.to_string())?
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpConnection {
    provider: String,
    name: String,
    scope: String,
    config_path: String,
    transport: String,
    enabled: bool,
}

#[tauri::command]
pub async fn mcp_discover(cwd: String) -> Result<Vec<McpConnection>, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let home = dirs_home().ok_or("Home directory not found")?;
        let project = expand_home(&cwd);
        let codex_home = std::env::var_os("CODEX_HOME").map(PathBuf::from);
        Ok(discover(Path::new(&home), &project, codex_home.as_deref()))
    })
    .await
    .map_err(|e| e.to_string())?
}

fn discover(home: &Path, project: &Path, codex_home_override: Option<&Path>) -> Vec<McpConnection> {
    let mut connections = Vec::new();
    let claude = home.join(".claude.json");
    if let Some(config) = read_json(&claude) {
        add_json_servers(
            &mut connections,
            "claude",
            "user",
            &claude,
            config.get("mcpServers"),
        );
        add_json_servers(
            &mut connections,
            "claude",
            "local",
            &claude,
            config
                .get("projects")
                .and_then(|projects| projects.get(project.to_string_lossy().as_ref()))
                .and_then(|entry| entry.get("mcpServers")),
        );
    }
    let codex_home = codex_home_override
        .map(Path::to_path_buf)
        .unwrap_or_else(|| home.join(".codex"));
    add_toml_file(
        &mut connections,
        "codex",
        "user",
        &codex_home.join("config.toml"),
    );

    // Project configuration is confined to the selected folder.
    add_json_file(
        &mut connections,
        "claude",
        "project",
        &project.join(".mcp.json"),
        "mcpServers",
    );
    add_toml_file(
        &mut connections,
        "codex",
        "project",
        &project.join(".codex/config.toml"),
    );
    connections.sort_by(|a, b| {
        (&a.provider, &a.name, &a.scope, &a.config_path).cmp(&(
            &b.provider,
            &b.name,
            &b.scope,
            &b.config_path,
        ))
    });
    connections
}

fn add_json_file(
    connections: &mut Vec<McpConnection>,
    provider: &str,
    scope: &str,
    path: &Path,
    key: &str,
) {
    if let Some(config) = read_json(path) {
        add_json_servers(connections, provider, scope, path, config.get(key));
    }
}

fn add_json_servers(
    connections: &mut Vec<McpConnection>,
    provider: &str,
    scope: &str,
    path: &Path,
    servers: Option<&Value>,
) {
    let Some(servers) = servers.and_then(Value::as_object) else {
        return;
    };
    for (name, config) in servers {
        if !config.is_object() {
            continue;
        }
        connections.push(McpConnection {
            provider: provider.into(),
            name: name.clone(),
            scope: scope.into(),
            config_path: path.to_string_lossy().into_owned(),
            transport: transport(config).into(),
            enabled: config.get("enabled").and_then(Value::as_bool) != Some(false)
                && config.get("disabled").and_then(Value::as_bool) != Some(true),
        });
    }
}

fn add_toml_file(connections: &mut Vec<McpConnection>, provider: &str, scope: &str, path: &Path) {
    let Some(raw) = std::fs::read_to_string(path).ok() else {
        return;
    };
    let Some(config) = toml::from_str::<toml::Value>(&raw).ok() else {
        return;
    };
    let Some(servers) = config.get("mcp_servers").and_then(toml::Value::as_table) else {
        return;
    };
    for (name, entry) in servers {
        connections.push(McpConnection {
            provider: provider.into(),
            name: name.clone(),
            scope: scope.into(),
            config_path: path.to_string_lossy().into_owned(),
            transport: if entry.get("url").is_some() {
                "http"
            } else {
                "stdio"
            }
            .into(),
            enabled: entry.get("enabled").and_then(toml::Value::as_bool) != Some(false),
        });
    }
}

fn transport(config: &Value) -> &str {
    config
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or_else(|| {
            if config.get("url").is_some() {
                "http"
            } else {
                "stdio"
            }
        })
}

fn read_json(path: &Path) -> Option<Value> {
    let raw = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&raw)
        .or_else(|_| serde_json::from_str(&strip_jsonc(&raw)))
        .ok()
}

/// Remove JSONC comments and trailing commas without touching quoted text.
fn strip_jsonc(raw: &str) -> String {
    let bytes = raw.as_bytes();
    let mut clean = Vec::with_capacity(bytes.len());
    let mut index = 0;
    let mut quoted = false;
    while index < bytes.len() {
        let byte = bytes[index];
        if quoted {
            clean.push(byte);
            if byte == b'\\' && index + 1 < bytes.len() {
                index += 1;
                clean.push(bytes[index]);
            } else if byte == b'"' {
                quoted = false;
            }
        } else if byte == b'"' {
            quoted = true;
            clean.push(byte);
        } else if byte == b'/' && bytes.get(index + 1) == Some(&b'/') {
            index += 2;
            while index < bytes.len() && bytes[index] != b'\n' {
                index += 1;
            }
            clean.push(b'\n');
        } else if byte == b'/' && bytes.get(index + 1) == Some(&b'*') {
            index += 2;
            while index + 1 < bytes.len() && !(bytes[index] == b'*' && bytes[index + 1] == b'/') {
                index += 1;
            }
            index = (index + 1).min(bytes.len() - 1);
        } else {
            clean.push(byte);
        }
        index += 1;
    }
    let mut result = Vec::with_capacity(clean.len());
    quoted = false;
    let mut escaped = false;
    for (index, byte) in clean.iter().enumerate() {
        if quoted {
            if escaped {
                escaped = false;
            } else if *byte == b'\\' {
                escaped = true;
            } else if *byte == b'"' {
                quoted = false;
            }
        } else if *byte == b'"' {
            quoted = true;
        }
        if !quoted
            && *byte == b','
            && clean[index + 1..]
                .iter()
                .find(|b| !b.is_ascii_whitespace())
                .is_some_and(|b| *b == b'}' || *b == b']')
        {
            continue;
        }
        result.push(*byte);
    }
    String::from_utf8(result).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_single_server_from_standard_json() {
        let (name, server) = server_from_json(
            "claude",
            "",
            r#"{"mcpServers":{"docs":{"command":"npx","args":["server"]}}}"#,
        )
        .unwrap();
        assert_eq!(name, "docs");
        assert_eq!(server["command"], "npx");
        assert!(server_from_json(
            "claude",
            "",
            r#"{"mcpServers":{"one":{"command":"npx"},"two":{"command":"node"}}}"#
        )
        .is_err());
        assert!(server_from_json(
            "claude",
            "different",
            r#"{"mcpServers":{"docs":{"command":"npx"}}}"#
        )
        .is_err());
    }

    #[test]
    fn jsonc_preserves_urls_and_removes_comments_and_trailing_commas() {
        let input = r#"{"mcp":{"servers":{"docs":{"url":"https://example.com/mcp",},},}, // comment
        }"#;
        let value: Value = serde_json::from_str(&strip_jsonc(input)).unwrap();
        assert_eq!(
            value["mcp"]["servers"]["docs"]["url"],
            "https://example.com/mcp"
        );
    }

    #[test]
    fn discovery_preserves_codex_enablement() {
        let root = std::env::temp_dir().join(format!("loci-mcp-enabled-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&root).unwrap();
        let path = root.join("config.toml");
        std::fs::write(
            &path,
            "[mcp_servers.off]\ncommand = 'node'\nenabled = false\n[mcp_servers.on]\ncommand = 'node'\n",
        ).unwrap();
        let mut found = Vec::new();
        add_toml_file(&mut found, "codex", "user", &path);
        assert_eq!(found.len(), 2);
        assert!(
            !found
                .iter()
                .find(|server| server.name == "off")
                .unwrap()
                .enabled
        );
        assert!(
            found
                .iter()
                .find(|server| server.name == "on")
                .unwrap()
                .enabled
        );
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[cfg(test)]
mod discovery_tests {
    use super::*;
    #[test]
    fn discovers_personal_and_selected_project_configuration_without_parent_scan() {
        let root = std::env::temp_dir().join(format!("loci-mcp-{}", uuid::Uuid::new_v4()));
        let home = root.join("home");
        let project = root.join("parent/project");
        std::fs::create_dir_all(home.join(".codex")).unwrap();
        std::fs::create_dir_all(project.join(".codex")).unwrap();
        std::fs::write(
            home.join(".claude.json"),
            r#"{"mcpServers":{"personal":{"command":"test"}}}"#,
        )
        .unwrap();
        std::fs::write(
            home.join(".codex/config.toml"),
            "[mcp_servers.codex_personal]\ncommand = 'test'\n",
        )
        .unwrap();
        std::fs::write(
            project.join(".mcp.json"),
            r#"{"mcpServers":{"project":{"url":"https://example.com"}}}"#,
        )
        .unwrap();
        std::fs::write(
            project.join(".codex/config.toml"),
            "[mcp_servers.codex_project]\ncommand = 'test'\n",
        )
        .unwrap();
        std::fs::write(
            project.parent().unwrap().join(".mcp.json"),
            r#"{"mcpServers":{"parent":{"command":"test"}}}"#,
        )
        .unwrap();
        let result = discover(&home, &project, None);
        assert_eq!(result.len(), 4);
        assert!(!result.iter().any(|connection| connection.name == "parent"));
        assert!(result
            .iter()
            .any(|connection| connection.name == "project" && connection.transport == "http"));
        std::fs::remove_dir_all(root).unwrap();
    }
}
