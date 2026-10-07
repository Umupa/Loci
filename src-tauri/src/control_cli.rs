//! The desktop executable also provides a small, JSON-only control client.
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::time::Duration;

use serde_json::{json, Value};

const APP_ACTIONS: [&str; 18] = [
    "models.list",
    "sessions.list",
    "sessions.read",
    "sessions.send",
    "sessions.draft",
    "sessions.start",
    "folders.list",
    "folders.move",
    "notes.list",
    "notes.read",
    "notes.write",
    "canvas.list",
    "canvas.get",
    "canvas.create",
    "canvas.rename",
    "canvas.delete",
    "canvas.read-data",
    "canvas.write-data",
];
const APP_USAGE: &str = r#"Loci app access — use in a thread enabled by /operator.

Usage: {exe} app ACTION [--json JSON | --input FILE|-] [--request-id ID]

Actions:
  models.list    {}  Available providers, models, settings and permission modes.
  sessions.list  {}  Project sessions with IDs, busy status and hasDraft.
  sessions.read  {"sessionId":"...","before":"<turnId>","limit":3,"maxChars":1200}
                  Read up to 3 recent user/assistant exchanges. Tools and
                  reasoning are omitted. Omit before for the newest page;
                  pass nextBefore from a result for older exchanges. maxChars
                  caps each message (200-6000, default 1200).
  sessions.send  {"sessionId":"...","prompt":"..."}
                  Submit a follow-up to an idle session in this project.
                  A busy session is rejected. Reuse --request-id on retries.
  sessions.draft {"sessionId":"...","prompt":"..."}
                  Save an unsent draft in an idle project session. Existing
                  drafts are preserved; send or remove one in Loci first.
                  Reuse --request-id on retries.
  sessions.start {"prompt":"...","harness":"codex","model":"codex:...",
                  "effort":"high","reveal":false,
                  "draft":false,
                  "placement":"right",
                  "besideSessionId":"<visible session ID>"}
                  Create a tab with the prompt, or set placement to right or
                  down to split a visible session pane. A split defaults to the
                  calling session; besideSessionId chooses another visible
                  session in this project, including one just created. Set
                  draft:true to save the prompt unsent; no agent turn runs.
                  Otherwise the turn is submitted.
                  Returns after creation/acceptance, not agent completion;
                  use its ID with folders.move immediately. Optional model,
                  effort, modelSettings and permission mode
                  use composer values. Omit
                  runtimeMode to inherit this
                  session's permission mode; set it to override. Run
                  models.list for allowed IDs. cwd is your project; no attachments.
  folders.list   {}  Folders in your current project.
  folders.move   {"sessionId":"...","folderId":"..."}
                  Or use "newFolderName":"Research" to create a folder.
  notes.list     {"limit":30,"offset":0}  Titles and short previews only.
  notes.read     {"id":"..."}  Full body of one note.
  notes.write    {"title":"Plan","body":"Markdown","tags":["work"]}
                  Create a note linked to this session and project. Omit title
                  to derive it from the body. Use {"id":"...","body":"..."}
                  to edit an existing note; title and tags are also optional.
                  Omitted fields stay unchanged. Reuse --request-id on retries.
  canvas.list    {}  Current project drawings, newest first; metadata only.
  canvas.get     {"id":"..."}  Metadata of one drawing; no scene data.
  canvas.create  {"title":"Plan"}  Create an empty drawing in this project.
                  Omit title to use "Untitled drawing". Returns id and title.
  canvas.rename  {"id":"...","title":"New title"}  Rename a drawing.
  canvas.delete  {"id":"..."}  Delete a drawing.
  canvas.read-data  {"id":"..."}  Read full scene data (dataJson) of a drawing
                  in this project, including pending edits in open panes.
  canvas.write-data {"id":"...","dataJson":"..."}  Replace a drawing's scene
                  with Excalidraw JSON. dataJson must be a valid JSON string
                  containing {"elements":[...],"appState":{...},"files":{}}.
                  Max 250000 UTF-8 bytes before JSON transport escaping.
                  Basic shapes may use Excalidraw programmatic elements with
                  x/y, optional id and label:{text:"..."}; IDs are retained.
                  Programmatic arrows bind with start:{id:"shape-id"} and
                  end:{id:"shape-id"}. Native scenes use native bindings.
                  Full scenes support images, frames and freehand elements.
                  MCP cameraUpdate/delete/restoreCheckpoint are not elements.
                  Writes update open panes. Read first to extend a drawing;
                  this replaces the whole scene, it does not merge elements.

The output is one JSON line: {"ok":true,"result":...} or {"ok":false,"error":"..."}.
Note and canvas results include a stable loci://note/ID or loci://canvas/ID url.
Successful writes include saved:true. In your reply, include [title](url) so
the user can open the saved resource directly inside Loci. These links do not
open a browser or launch Loci from another application.
Use --input - to pass JSON on stdin. Never print Loci credentials.
Keep the same --request-id when retrying a call after an uncertain result.
"#;

/// Quote for the shell the lead agent actually runs commands in, and only when
/// the path needs it. The path is absolute, so a leading slash means a POSIX
/// shell — where a backslash escapes rather than separates, and so is never
/// safe bare.
fn quoted(value: &str) -> String {
    if !value.starts_with('/') {
        return if value.contains([' ', '\t', '"']) {
            format!("\"{}\"", value.replace('"', ""))
        } else {
            value.into()
        };
    }
    if value
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || "._/-:".contains(c))
    {
        value.into()
    } else {
        format!("'{}'", value.replace('\'', r"'\''"))
    }
}

pub fn app_help() -> String {
    let exe = std::env::current_exe()
        .map(|path| quoted(&path.to_string_lossy()))
        .unwrap_or_else(|_| "loci".into());
    APP_USAGE.replace("{exe}", &exe)
}

enum Parsed {
    Help,
    Call(String, Value, String),
}

pub fn run_app(args: Vec<String>) -> i32 {
    run_mode(args)
}

fn run_mode(args: Vec<String>) -> i32 {
    let parsed = match parse_args(&args) {
        Ok(parsed) => parsed,
        Err(error) => {
            println!("{}", json!({"ok": false, "error": error}));
            return 1;
        }
    };
    let (action, input, request_id) = match parsed {
        Parsed::Help => {
            println!("{}", app_help());
            return 0;
        }
        Parsed::Call(action, input, request_id) => (action, input, request_id),
    };
    match send(&action, &input, &request_id) {
        Ok(mut value) => {
            if value.get("ok").and_then(Value::as_bool) == Some(true) {
                println!("{value}");
                return 0;
            }
            value = with_retry_hint(value, &request_id);
            println!("{value}");
            1
        }
        Err(Failure { error, sent }) => {
            // The call may have reached the run even though its answer was
            // lost. Hand back the request ID so a retry cannot duplicate it.
            let mut response = json!({"ok": false, "error": error});
            if sent {
                response["requestId"] = json!(request_id);
                response["retryWith"] = json!(format!("--request-id {request_id}"));
            }
            println!("{response}");
            1
        }
    }
}

fn with_retry_hint(mut value: Value, request_id: &str) -> Value {
    // A denied app call never reached the executor. Repeating the same ID
    // cannot grant access, and suggesting it sends agents in loops.
    if value.get("retryable").and_then(Value::as_bool) == Some(false) {
        return value;
    }
    if let Some(object) = value.as_object_mut() {
        object
            .entry("requestId")
            .or_insert_with(|| json!(request_id));
        object
            .entry("retryWith")
            .or_insert_with(|| json!(format!("--request-id {request_id}")));
    }
    value
}

struct Failure {
    error: String,
    /// The request was already on the wire, so the run may have applied it.
    sent: bool,
}
fn unsent(error: impl Into<String>) -> Failure {
    Failure {
        error: error.into(),
        sent: false,
    }
}
fn sent(error: impl Into<String>) -> Failure {
    Failure {
        error: error.into(),
        sent: true,
    }
}

fn send(action: &str, input: &Value, request_id: &str) -> Result<Value, Failure> {
    let endpoint_key = "LOCI_APP_ENDPOINT";
    let token_key = "LOCI_APP_TOKEN";
    let endpoint = std::env::var(endpoint_key)
        .map_err(|_| unsent("No Loci app connection. Start this agent turn in Loci."))?;
    let token = std::env::var(token_key)
        .map_err(|_| unsent("No Loci session credential. Start the agent from Loci."))?;
    let address: SocketAddr = endpoint
        .parse()
        .map_err(|_| unsent("Invalid Loci endpoint"))?;
    if !address.ip().is_loopback() {
        return Err(unsent("Loci control only connects to localhost"));
    }
    let mut stream = TcpStream::connect_timeout(&address, Duration::from_secs(3))
        .map_err(|error| {
            unsent(format!(
                "Cannot connect to Loci at {address}: {error}. The app may have restarted, or this agent's sandbox may be blocking localhost."
            ))
        })?;
    stream
        .set_read_timeout(Some(Duration::from_secs(40)))
        .map_err(|e| unsent(e.to_string()))?;
    stream
        .set_write_timeout(Some(Duration::from_secs(5)))
        .map_err(|e| unsent(e.to_string()))?;
    writeln!(
        stream,
        "{}",
        json!({"token":token,"action":action,"input":input,"requestId":request_id,"namespace":"app"})
    )
    .map_err(|e| sent(e.to_string()))?;
    let mut line = String::new();
    let max_response: u64 = 4_000_000;
    BufReader::new(stream)
        .take(max_response + 1)
        .read_line(&mut line)
        .map_err(|e| sent(format!("No reply from Loci: {e}")))?;
    if line.len() > max_response as usize {
        return Err(sent("Loci response is too large"));
    }
    serde_json::from_str(&line).map_err(|_| sent("Loci returned an invalid response"))
}

fn read_capped(mut source: impl Read) -> Result<String, String> {
    let mut raw = String::new();
    source
        .by_ref()
        .take(262_145)
        .read_to_string(&mut raw)
        .map_err(|e| e.to_string())?;
    if raw.len() > 262_144 {
        return Err("Input exceeds 256 KiB".into());
    }
    Ok(raw)
}

fn parse_args(args: &[String]) -> Result<Parsed, String> {
    let is_help = |value: &str| matches!(value, "help" | "--help" | "-h");
    let Some(action) = args.first() else {
        return Ok(Parsed::Help);
    };
    if is_help(action) {
        return Ok(Parsed::Help);
    }
    let action = action.clone();
    if !APP_ACTIONS.contains(&action.as_str()) {
        return Err(format!(
            "Unknown action: {action}. Use one of: {}. Run app --help.",
            APP_ACTIONS.join(", ")
        ));
    }
    let mut input = None;
    let mut request_id = uuid::Uuid::new_v4().to_string();
    let mut index = 1;
    while index < args.len() {
        let flag = &args[index];
        // `app notes.list --help` should explain the command, not fail.
        if is_help(flag) {
            return Ok(Parsed::Help);
        }
        if !flag.starts_with("--") {
            return Err(format!(
                "Unexpected argument: {flag}. Pass the JSON object as --json '<JSON>'."
            ));
        }
        let value = args.get(index + 1).ok_or_else(|| {
            format!("Missing value for {flag}. Run app --help for the argument list.")
        })?;
        match flag.as_str() {
            "--request-id" => request_id = value.clone(),
            "--json" | "--input" => {
                if input.is_some() {
                    return Err("Supply only one input".into());
                }
                let raw = if flag == "--json" {
                    if value.len() > 262_144 {
                        return Err("Input exceeds 256 KiB".into());
                    }
                    value.clone()
                } else if value == "-" {
                    read_capped(std::io::stdin())?
                } else {
                    read_capped(std::fs::File::open(value).map_err(|e| e.to_string())?)?
                };
                let parsed: Value = serde_json::from_str(&raw)
                    .map_err(|e| format!("Invalid JSON: {e}. Pass one JSON object, e.g. --json '{{\"sessionId\":\"...\"}}'."))?;
                if !parsed.is_object() {
                    return Err("Input must be a JSON object".into());
                }
                input = Some(parsed);
            }
            _ => {
                return Err(format!(
                    "Unknown option: {flag}. Supported: --json, --input, --request-id."
                ))
            }
        }
        index += 2;
    }
    if request_id.is_empty() || request_id.len() > 128 {
        return Err("Invalid request ID".into());
    }
    if !request_id
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
    {
        return Err("App request IDs may contain only letters, digits, - and _".into());
    }
    Ok(Parsed::Call(
        action,
        input.unwrap_or_else(|| json!({})),
        request_id,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(|s| s.to_string()).collect()
    }
    fn call(values: &[&str]) -> Result<(String, Value, String), String> {
        match parse_args(&args(values))? {
            Parsed::Call(action, input, id) => Ok((action, input, id)),
            Parsed::Help => Err("help".into()),
        }
    }
    #[test]
    fn validates_inputs_without_invoking_a_shell() {
        let (_, input, id) = call(&[
            "sessions.start",
            "--json",
            r#"{"prompt":"$(touch nope) `hello`\nnext"}"#,
            "--request-id",
            "retry-1",
        ])
        .unwrap();
        assert_eq!(id, "retry-1");
        assert_eq!(input["prompt"], "$(touch nope) `hello`\nnext");
        assert!(call(&["sessions.start", "--json", "[]"]).is_err());
        assert!(call(&["sessions.start", "--json", "{}", "--json", "{}"]).is_err());
        assert!(call(&["unknown"]).is_err());
    }
    #[test]
    fn explains_help_and_malformed_invocations() {
        assert!(matches!(parse_args(&args(&[])), Ok(Parsed::Help)));
        assert!(matches!(parse_args(&args(&["--help"])), Ok(Parsed::Help)));
        // Agents commonly probe a subcommand for its own usage text.
        assert!(matches!(
            parse_args(&args(&["sessions.start", "--help"])),
            Ok(Parsed::Help)
        ));
        assert!(call(&["sessions.read", r#"{"sessionId":"x"}"#])
            .unwrap_err()
            .contains("--json"));
        assert!(call(&["sessions.read", "--json"])
            .unwrap_err()
            .contains("--help"));
        assert!(call(&["sessions.read", "--sessionId", "x"])
            .unwrap_err()
            .contains("Unknown option"));
        assert!(call(&["sessions.read", "--json", "{sessionId}"])
            .unwrap_err()
            .contains("Invalid JSON"));
    }
    #[test]
    fn help_names_every_action_and_the_real_executable() {
        let text = app_help();
        for action in APP_ACTIONS {
            assert!(text.contains(action), "help omits {action}");
        }
        assert!(!text.contains("{exe}"));
        assert!(text.contains("--request-id"));
    }
    #[test]
    fn quotes_the_control_path_only_when_the_shell_needs_it() {
        assert_eq!(
            quoted("/Applications/Loci.app/Contents/MacOS/loci"),
            "/Applications/Loci.app/Contents/MacOS/loci"
        );
        assert_eq!(quoted("/Users/a b/Loci"), "'/Users/a b/Loci'");
        assert_eq!(quoted("C:\\Tools\\loci.exe"), "C:\\Tools\\loci.exe");
        assert_eq!(
            quoted("C:\\Program Files\\Loci\\loci.exe"),
            "\"C:\\Program Files\\Loci\\loci.exe\""
        );
        // A backslash escapes in a POSIX shell, so bare would rewrite the path.
        assert_eq!(quoted("/Users/a\\b/Loci"), "'/Users/a\\b/Loci'");
        assert_eq!(quoted("/Users/it's/Loci"), r"'/Users/it'\''s/Loci'");
    }
    #[test]
    fn app_mode_exposes_only_app_actions_and_safe_request_ids() {
        assert!(matches!(
            parse_args(&args(&["notes.list"])),
            Ok(Parsed::Call(_, _, _))
        ));
        for action in ["sessions.read", "sessions.send", "sessions.draft"] {
            assert!(matches!(
                parse_args(&args(&[action, "--json", r#"{"sessionId":"other"}"#])),
                Ok(Parsed::Call(_, _, _))
            ));
            assert!(app_help().contains(action));
        }
        assert!(app_help().contains("draft:true"));
        assert!(app_help().contains("inherit this"));
        assert!(parse_args(&args(&["unknown.action"])).is_err());
        assert!(parse_args(&args(&["sessions.start", "--request-id", "bad/id"])).is_err());
        assert!(app_help().contains("notes.read"));
        assert!(app_help().contains("notes.write"));
        for action in [
            "canvas.list",
            "canvas.get",
            "canvas.create",
            "canvas.rename",
            "canvas.delete",
            "canvas.read-data",
            "canvas.write-data",
        ] {
            assert!(matches!(
                parse_args(&args(&[action, "--json", r#"{}"#])),
                Ok(Parsed::Call(parsed, _, _)) if parsed == action
            ));
            assert!(app_help().contains(action));
        }
    }

    #[test]
    fn inactive_app_turn_does_not_suggest_retries() {
        let denied = with_retry_hint(json!({"ok":false,"retryable":false}), "id-1");
        assert!(denied.get("retryWith").is_none());
        assert!(denied.get("requestId").is_none());
        let uncertain = with_retry_hint(json!({"ok":false,"error":"timeout"}), "id-1");
        assert_eq!(uncertain["retryWith"], "--request-id id-1");
    }
}
