//! The desktop executable also provides a small control client: the JSON-only
//! `app` actions of /operator, and the built-in canvas and learning tools for
//! agent CLIs that cannot be given an MCP server.
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{mpsc, Arc, Mutex};
use std::time::{Duration, Instant};

use serde_json::{json, Value};

const APP_ACTIONS: [&str; 33] = [
    "models.list",
    "sessions.list",
    "sessions.read",
    "sessions.send",
    "sessions.draft",
    "sessions.stop",
    "sessions.archive",
    "sessions.delete",
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
    "soul.read",
    "soul.update",
    "memory.read",
    "memory.search",
    "memory.add",
    "memory.replace",
    "memory.remove",
    "habits.list",
    "habits.add",
    "habits.update",
    "habits.run",
    "habits.remove",
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

An agent works on several projects rather than in one. Its sessions.*,
folders.* and canvas.* actions also take "project":"<path or name>" to choose
which; it may be left out with one project. Ordinary sessions cannot pass it.
  sessions.stop    {"sessionId":"..."}  Cancel another session's current turn.
  sessions.archive {"sessionId":"..."}  Stop it and put it away; it can be restored.
  sessions.delete  {"sessionId":"..."}  Remove it for good. The user is asked to
                  confirm first; the call fails if they decline.
                  None of these can target the caller, an agent's chat or a habit run.
  In an agent's chat, sessions.start reports the session's result back when it
  stops; pass "notifyOnComplete":false to opt out, or "notifyOnComplete":true
  on sessions.send to hear back about a follow-up.

Only in an agent's own conversation:
  soul.read      {}  Its standing instructions (SOUL.md) and their hash.
  soul.update    {"text":"<complete Markdown>","expectedHash":"<from soul.read>"}
                  Replace them, only at the user's request. A stale hash is
                  rejected: read again and reapply the change.
  memory.add     {"fact":"...","until":"YYYY-MM-DD","topic":"<name>"}
                  Remember one dated fact; until and topic are optional.
  memory.replace {"find":"<text of the old entry>","fact":"..."}
                  Supersede an entry that changed.
  memory.remove  {"find":"..."}  Drop an entry that was wrong.
  memory.read    {"topic":"<name>"}  One topic file, or MEMORY.md without topic.
  memory.search  {"query":"...","since":"7d"}  Search memory, topic notes and
                  the archive. since is a date or a span like 24h, 7d, 2w.
  habits.list    {}  What it does on its own, with schedules and last outcomes.
  habits.add     {"name":"Morning CI check","instructions":"...",
                  "schedule":{"kind":"weekdays","time":"09:00"}}
                  kind is hourly (with "minute":0-59), daily, weekdays or
                  weekly (with "dayOfWeek":0-6, 0 is Sunday). Times are local.
                  Add one only once the user agrees.
  habits.update  {"id":"...","enabled":false}  Also name, instructions, schedule.
  habits.run     {"id":"..."}  Run it now; the schedule is left alone.
  habits.remove  {"id":"..."}

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
    send_to("app", action, input, request_id)
}

fn send_to(
    namespace: &str,
    action: &str,
    input: &Value,
    request_id: &str,
) -> Result<Value, Failure> {
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
        json!({"token":token,"action":action,"input":input,"requestId":request_id,"namespace":namespace})
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

const APP_INPUT_MAX: usize = 262_144;

fn read_capped(mut source: impl Read, max: usize) -> Result<String, String> {
    let mut raw = String::new();
    source
        .by_ref()
        .take(max as u64 + 1)
        .read_to_string(&mut raw)
        .map_err(|e| e.to_string())?;
    if raw.len() > max {
        return Err(format!("Input exceeds {}", size_label(max)));
    }
    Ok(raw)
}

fn size_label(bytes: usize) -> String {
    if bytes >= 1024 * 1024 {
        format!("{} MiB", bytes / (1024 * 1024))
    } else {
        format!("{} KiB", bytes / 1024)
    }
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
                    if value.len() > APP_INPUT_MAX {
                        return Err("Input exceeds 256 KiB".into());
                    }
                    value.clone()
                } else if value == "-" {
                    read_capped(std::io::stdin(), APP_INPUT_MAX)?
                } else {
                    read_capped(
                        std::fs::File::open(value).map_err(|e| e.to_string())?,
                        APP_INPUT_MAX,
                    )?
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

/// A canvas save may carry the 5 MB of elements the official server accepts.
const TOOL_INPUT_MAX: usize = 6 * 1024 * 1024;
const TOOL_START_TIMEOUT: Duration = Duration::from_secs(30);
/// Longer than the window's own limit, so its answer is the one reported.
const TOOL_CALL_TIMEOUT: Duration = Duration::from_secs(60);
/// The tools an agent may call. The servers also list tools that only the
/// official drawing widget uses; those stay out of reach here as they do for
/// agents that attach the servers over MCP. The window knows the same names
/// (`CANVAS_MCP_TOOLS` and `LEARN_MCP_TOOLS` in `src/features`), which is how
/// it names and answers approvals for these calls; keep the lists in step.
const CANVAS_TOOLS: [&str; 5] = [
    "read_me",
    "create_view",
    "read_widget_context",
    "get_elements",
    "update_elements",
];
const LEARN_TOOLS: [&str; 5] = [
    "map_read",
    "map_init",
    "map_sketch",
    "map_record",
    "revisit",
];
const TOOL_USAGE: &str = r#"Loci {subject} — call one tool during an agent turn started in Loci.

Usage: {exe} {namespace} TOOL [--json JSON | --input FILE|-]
       {exe} {namespace} --help

A tool takes one JSON object as its arguments; omit it for a tool that needs
none. Pass large arguments as a file (--input FILE) or on stdin (--input -).
The output is the tool's reply as text. The exit code is 0 only when the call
succeeded; otherwise the output says what to change.
The CLI uses a session credential already in your environment; never print it.
"#;

fn tools_of(namespace: &str) -> &'static [&'static str] {
    if namespace == "learn" {
        &LEARN_TOOLS
    } else {
        &CANVAS_TOOLS
    }
}

pub fn tool_help(namespace: &str) -> String {
    let exe = std::env::current_exe()
        .map(|path| quoted(&path.to_string_lossy()))
        .unwrap_or_else(|_| "loci".into());
    let subject = if namespace == "learn" {
        "learning map tools"
    } else {
        "canvas tools"
    };
    TOOL_USAGE
        .replace("{exe}", &exe)
        .replace("{namespace}", namespace)
        .replace("{subject}", subject)
}

enum ToolParsed {
    Help,
    Call(String, Value),
}

/// Run one tool of a built-in server: `canvas` is the Excalidraw server,
/// `learn` the learning map. The same server process an MCP client would
/// attach is started for the call, so the tools and their rules are identical.
pub fn run_tool(namespace: &str, args: Vec<String>) -> i32 {
    let parsed = match parse_tool_args(namespace, &args) {
        Ok(parsed) => parsed,
        Err(error) => {
            println!("Error: {error}");
            return 1;
        }
    };
    let outcome = match &parsed {
        ToolParsed::Help => {
            list_tools(namespace).map(|tools| (format!("{}\n{tools}", tool_help(namespace)), false))
        }
        ToolParsed::Call(tool, input) => call_tool(namespace, tool, input),
    };
    match outcome {
        Ok((text, failed)) => {
            println!("{text}");
            i32::from(failed)
        }
        Err(error) => {
            if matches!(parsed, ToolParsed::Help) {
                println!("{}", tool_help(namespace));
            }
            println!("Error: {error}");
            1
        }
    }
}

fn parse_tool_args(namespace: &str, args: &[String]) -> Result<ToolParsed, String> {
    let is_help = |value: &str| matches!(value, "help" | "--help" | "-h");
    let Some(tool) = args.first() else {
        return Ok(ToolParsed::Help);
    };
    if is_help(tool) {
        return Ok(ToolParsed::Help);
    }
    let tools = tools_of(namespace);
    if !tools.contains(&tool.as_str()) {
        return Err(format!(
            "Unknown tool: {tool}. Use one of: {}. Run {namespace} --help.",
            tools.join(", ")
        ));
    }
    let mut input = None;
    let mut index = 1;
    while index < args.len() {
        let flag = &args[index];
        if is_help(flag) {
            return Ok(ToolParsed::Help);
        }
        if !matches!(flag.as_str(), "--json" | "--input") {
            return Err(format!(
                "Unexpected argument: {flag}. Pass the tool's arguments as --json '<JSON>' or --input FILE."
            ));
        }
        let value = args
            .get(index + 1)
            .ok_or_else(|| format!("Missing value for {flag}."))?;
        if input.is_some() {
            return Err("Supply only one input".into());
        }
        let raw = if flag == "--json" {
            if value.len() > TOOL_INPUT_MAX {
                return Err(format!("Input exceeds {}", size_label(TOOL_INPUT_MAX)));
            }
            value.clone()
        } else if value == "-" {
            read_capped(std::io::stdin(), TOOL_INPUT_MAX)?
        } else {
            read_capped(
                std::fs::File::open(value).map_err(|e| format!("Cannot read {value}: {e}"))?,
                TOOL_INPUT_MAX,
            )?
        };
        // The parser's message names a position, never the text it read.
        let parsed: Value = serde_json::from_str(&raw).map_err(|e| {
            format!("Invalid JSON: {e}. Pass the tool's arguments as one JSON object.")
        })?;
        if !parsed.is_object() {
            return Err("Input must be a JSON object".into());
        }
        input = Some(parsed);
        index += 2;
    }
    Ok(ToolParsed::Call(
        tool.clone(),
        input.unwrap_or_else(|| json!({})),
    ))
}

/// Ask the running app how to start the server. It already knows where its
/// resources and a JavaScript runtime are, and it refuses a session that may
/// not use the server now.
fn builtin_server(namespace: &str) -> Result<(String, Vec<String>), String> {
    let reply = send_to(
        namespace,
        "mcp.server",
        &json!({}),
        &uuid::Uuid::new_v4().to_string(),
    )
    .map_err(|failure| failure.error)?;
    if reply.get("ok").and_then(Value::as_bool) != Some(true) {
        return Err(reply
            .get("error")
            .and_then(Value::as_str)
            .unwrap_or("Loci refused the request")
            .to_owned());
    }
    let server = &reply["result"];
    let command = server
        .get("command")
        .and_then(Value::as_str)
        .filter(|command| !command.is_empty())
        .ok_or("Loci did not say how to start its tools")?;
    let args = server
        .get("args")
        .and_then(Value::as_array)
        .map(|args| {
            args.iter()
                .filter_map(|arg| arg.as_str().map(str::to_owned))
                .collect()
        })
        .unwrap_or_default();
    Ok((command.to_owned(), args))
}

fn call_tool(namespace: &str, tool: &str, input: &Value) -> Result<(String, bool), String> {
    let (command, args) = builtin_server(namespace)?;
    let mut server = ToolServer::start(&command, &args)?;
    let result = server.request(
        "tools/call",
        json!({"name": tool, "arguments": input}),
        TOOL_CALL_TIMEOUT,
    )?;
    let failed = result.get("isError").and_then(Value::as_bool) == Some(true);
    Ok((tool_text(&result), failed))
}

fn list_tools(namespace: &str) -> Result<String, String> {
    let (command, args) = builtin_server(namespace)?;
    let mut server = ToolServer::start(&command, &args)?;
    let result = server.request("tools/list", json!({}), TOOL_START_TIMEOUT)?;
    Ok(tools_text(namespace, &result))
}

/// What an MCP client would show the model: the reply's text blocks.
fn tool_text(result: &Value) -> String {
    let blocks: Vec<&str> = result
        .get("content")
        .and_then(Value::as_array)
        .map(|content| {
            content
                .iter()
                .filter_map(|block| block.get("text").and_then(Value::as_str))
                .collect()
        })
        .unwrap_or_default();
    if !blocks.is_empty() {
        return blocks.join("\n");
    }
    match result.get("structuredContent") {
        Some(data) if !data.is_null() => data.to_string(),
        _ => "The tool returned no text.".into(),
    }
}

fn tools_text(namespace: &str, result: &Value) -> String {
    let allowed = tools_of(namespace);
    let mut text = String::from("Tools:\n");
    for tool in result
        .get("tools")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let Some(name) = tool.get("name").and_then(Value::as_str) else {
            continue;
        };
        if !allowed.contains(&name) {
            continue;
        }
        text.push_str(&format!("\n## {name}"));
        if let Some(title) = tool.get("title").and_then(Value::as_str) {
            text.push_str(&format!(" — {title}"));
        }
        text.push('\n');
        if let Some(description) = tool.get("description").and_then(Value::as_str) {
            text.push_str(description.trim());
            text.push('\n');
        }
        if let Some(schema) = tool.get("inputSchema") {
            text.push_str(&format!("Arguments (JSON Schema): {schema}\n"));
        }
    }
    text
}

/// One short-lived connection to a built-in stdio MCP server.
struct ToolServer {
    child: Child,
    stdin: ChildStdin,
    lines: mpsc::Receiver<String>,
    stderr: Arc<Mutex<String>>,
    stderr_reader: Option<std::thread::JoinHandle<()>>,
    next_id: u64,
}

impl ToolServer {
    /// The server inherits this process's environment, and with it the
    /// session credential it uses to reach the session's Loci window.
    fn start(command: &str, args: &[String]) -> Result<Self, String> {
        let mut child = Command::new(command)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|error| format!("Cannot start Loci's tools ({command}): {error}"))?;
        let (Some(stdin), Some(stdout)) = (child.stdin.take(), child.stdout.take()) else {
            let _ = child.kill();
            return Err("Cannot reach Loci's tools".into());
        };
        let (tx, lines) = mpsc::channel();
        std::thread::spawn(move || {
            for line in BufReader::new(stdout).lines().map_while(Result::ok) {
                if tx.send(line).is_err() {
                    break;
                }
            }
        });
        let stderr = Arc::new(Mutex::new(String::new()));
        let stderr_reader = child.stderr.take().map(|pipe| {
            let seen = stderr.clone();
            std::thread::spawn(move || {
                for line in BufReader::new(pipe).lines().map_while(Result::ok) {
                    let Ok(mut seen) = seen.lock() else { break };
                    // Enough to explain a failed start; keep draining after that.
                    if seen.len() < 4_000 {
                        seen.push_str(&line);
                        seen.push('\n');
                    }
                }
            })
        });
        let mut server = Self {
            child,
            stdin,
            lines,
            stderr,
            stderr_reader,
            next_id: 0,
        };
        server.request(
            "initialize",
            json!({
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "loci-cli", "version": env!("CARGO_PKG_VERSION")},
            }),
            TOOL_START_TIMEOUT,
        )?;
        server.write(&json!({"jsonrpc": "2.0", "method": "notifications/initialized"}))?;
        Ok(server)
    }

    fn write(&mut self, message: &Value) -> Result<(), String> {
        let written = writeln!(self.stdin, "{message}").and_then(|_| self.stdin.flush());
        written.map_err(|_| self.stopped())
    }

    fn stopped(&self) -> String {
        // Let the server's last words arrive before quoting them: its error
        // output ends when it exits, which is what stopping usually means.
        let deadline = Instant::now() + Duration::from_secs(2);
        while Instant::now() < deadline
            && self
                .stderr_reader
                .as_ref()
                .is_some_and(|reader| !reader.is_finished())
        {
            std::thread::sleep(Duration::from_millis(10));
        }
        self.failure("Loci's tools stopped before answering.")
    }

    /// The reason, with what the server itself printed about it.
    fn failure(&self, message: &str) -> String {
        let seen = self
            .stderr
            .lock()
            .map(|seen| seen.trim().to_owned())
            .unwrap_or_default();
        if seen.is_empty() {
            message.to_owned()
        } else {
            format!("{message}\n{seen}")
        }
    }

    fn request(&mut self, method: &str, params: Value, timeout: Duration) -> Result<Value, String> {
        self.next_id += 1;
        let id = self.next_id;
        self.write(&json!({"jsonrpc": "2.0", "id": id, "method": method, "params": params}))?;
        let deadline = Instant::now() + timeout;
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            let line = match self.lines.recv_timeout(left) {
                Ok(line) => line,
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    return Err(self.failure("Loci's tools did not answer in time."))
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => return Err(self.stopped()),
            };
            // Notifications and requests from the server are not this call's reply.
            let Ok(message) = serde_json::from_str::<Value>(&line) else {
                continue;
            };
            if message.get("id").and_then(Value::as_u64) != Some(id) {
                continue;
            }
            if let Some(error) = message.get("error") {
                return Err(error
                    .get("message")
                    .and_then(Value::as_str)
                    .unwrap_or("Loci's tools rejected the request")
                    .to_owned());
            }
            return Ok(message.get("result").cloned().unwrap_or(Value::Null));
        }
    }
}

impl Drop for ToolServer {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
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

    fn tool(namespace: &str, values: &[&str]) -> Result<(String, Value), String> {
        match parse_tool_args(namespace, &args(values))? {
            ToolParsed::Call(tool, input) => Ok((tool, input)),
            ToolParsed::Help => Err("help".into()),
        }
    }
    #[test]
    fn tool_mode_takes_a_known_tool_and_one_json_object() {
        let (name, input) = tool(
            "canvas",
            &["read_widget_context", "--json", r#"{"checkpointId":"abc"}"#],
        )
        .unwrap();
        assert_eq!(name, "read_widget_context");
        assert_eq!(input["checkpointId"], "abc");
        // A tool without arguments is called with an empty object.
        assert_eq!(tool("learn", &["map_read"]).unwrap().1, json!({}));
        for values in [
            &["create_view", "--json", "[]"][..],
            &["create_view", "--json", "{}", "--json", "{}"],
            &["create_view", "--json"],
            &["create_view", "{}"],
            &["create_view", "--request-id", "x"],
        ] {
            assert!(tool("canvas", values).is_err(), "{values:?}");
        }
        assert!(matches!(
            parse_tool_args("canvas", &args(&[])),
            Ok(ToolParsed::Help)
        ));
        assert!(matches!(
            parse_tool_args("learn", &args(&["map_record", "--help"])),
            Ok(ToolParsed::Help)
        ));
    }
    #[test]
    fn tool_mode_reaches_only_the_tools_agents_are_given() {
        // The official widget's own tools would replace a whole drawing.
        for hidden in ["save_checkpoint", "read_checkpoint", "export_to_excalidraw"] {
            let error = tool("canvas", &[hidden]).unwrap_err();
            assert!(error.contains("Unknown tool"), "{error}");
        }
        // Each server has its own tools.
        assert!(tool("canvas", &["map_read"]).is_err());
        assert!(tool("learn", &["create_view"]).is_err());
        let listed = tools_text(
            "canvas",
            &json!({"tools": [
                {"name": "create_view", "title": "Draw", "description": " Draws. ", "inputSchema": {"type": "object"}},
                {"name": "save_checkpoint", "description": "Widget only"},
            ]}),
        );
        assert!(listed.contains(
            "## create_view — Draw\nDraws.\nArguments (JSON Schema): {\"type\":\"object\"}"
        ));
        assert!(!listed.contains("save_checkpoint"));
    }
    #[test]
    fn tool_mode_never_echoes_a_file_it_could_not_parse() {
        let path = std::env::temp_dir().join(format!("loci-tool-input-{}", uuid::Uuid::new_v4()));
        std::fs::write(&path, "secret-material not json").unwrap();
        let error = tool(
            "canvas",
            &["get_elements", "--input", &path.to_string_lossy()],
        )
        .unwrap_err();
        std::fs::remove_file(&path).unwrap();
        assert!(error.contains("Invalid JSON"), "{error}");
        assert!(!error.contains("secret-material"), "{error}");
    }
    #[test]
    fn tool_replies_print_as_the_text_a_model_would_be_shown() {
        assert_eq!(
            tool_text(&json!({"content": [
                {"type": "text", "text": "Saved to Loci: [Plan](loci://canvas/c1)."},
                {"type": "text", "text": "Checkpoint id: \"abc\""},
            ], "structuredContent": {"saved": true}})),
            "Saved to Loci: [Plan](loci://canvas/c1).\nCheckpoint id: \"abc\""
        );
        assert_eq!(
            tool_text(&json!({"content": [], "structuredContent": {"revision": 3}})),
            r#"{"revision":3}"#
        );
        assert_eq!(tool_text(&json!({})), "The tool returned no text.");
        assert!(tool_help("learn").contains(" learn TOOL "));
        assert!(tool_help("canvas").contains("canvas tools"));
        assert!(!tool_help("canvas").contains("{exe}"));
    }
    /// The same handshake an attached MCP client makes, against the servers
    /// that ship with the app. Listing tools needs no Loci session.
    #[test]
    fn tool_mode_speaks_mcp_to_the_bundled_servers() {
        let version = Command::new("node").arg("--version").output();
        let Ok(version) = version else { return };
        // The Excalidraw bridge needs Node 20.11; the check lives in canvas_mcp.rs.
        let version = String::from_utf8_lossy(&version.stdout).into_owned();
        let mut parts = version.trim().trim_start_matches('v').split('.');
        let major: u32 = parts.next().and_then(|part| part.parse().ok()).unwrap_or(0);
        let minor: u32 = parts.next().and_then(|part| part.parse().ok()).unwrap_or(0);
        if major < 20 || (major == 20 && minor < 11) {
            return;
        }
        let resources = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("resources");
        for (namespace, script) in [
            ("learn", "learn-mcp/loci-learn.mjs"),
            ("canvas", "excalidraw-mcp/loci-bridge.mjs"),
        ] {
            let script = resources.join(script).to_string_lossy().into_owned();
            let mut server = ToolServer::start("node", &[script]).unwrap();
            let listed = server
                .request("tools/list", json!({}), TOOL_START_TIMEOUT)
                .unwrap();
            let text = tools_text(namespace, &listed);
            // Every tool the CLI accepts exists on the server, and is documented.
            for name in tools_of(namespace) {
                assert!(
                    text.contains(&format!("\n## {name}")),
                    "{namespace} lacks {name}"
                );
            }
            assert!(text.contains("Arguments (JSON Schema): {"));
        }
        // A command that is not an MCP server fails with its own words.
        let error = ToolServer::start(
            "node",
            &[
                "--eval".into(),
                "console.error('no runtime here'); process.exit(3)".into(),
            ],
        )
        .err()
        .unwrap();
        assert!(error.contains("stopped before answering"), "{error}");
        assert!(error.contains("no runtime here"), "{error}");
    }
}
