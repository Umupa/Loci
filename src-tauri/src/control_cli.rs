//! The desktop executable also provides a small control client: the JSON-only
//! `app` actions of the Loci app CLI.
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::time::Duration;

use serde_json::{json, Value};

const APP_ACTIONS: [&str; 35] = [
    "models.list",
    "sessions.list",
    "sessions.read",
    "sessions.send",
    "sessions.draft",
    "sessions.stop",
    "sessions.archive",
    "sessions.delete",
    "sessions.start",
    "notes.list",
    "notes.read",
    "notes.write",
    "agent.rename",
    "soul.read",
    "soul.update",
    "memory.read",
    "memory.search",
    "memory.add",
    "memory.replace",
    "memory.remove",
    "documents.list",
    "documents.read",
    "documents.write",
    "documents.translate",
    "guides.write",
    "courses.list",
    "courses.read",
    "courses.write",
    "courses.delete",
    "lessons.read",
    "lessons.write",
    "lessons.questions",
    "glossary.read",
    "glossary.write",
    "glossary.remove",
];
const APP_USAGE: &str = r#"Loci app access — available in agent chats.

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
                  "draft":false}
                  Start a session with the prompt. It runs in the background;
                  reveal:true shows it in the mentor's reader. There are no
                  tabs or panes: placement and besideSessionId are accepted
                  for older requests and ignored. Set
                  draft:true to save the prompt unsent; no agent turn runs.
                  Otherwise the turn is submitted.
                  Returns after creation/acceptance, not agent completion.
                  Optional model, effort, modelSettings and permission mode
                  use composer values. Omit
                  runtimeMode to inherit this
                  session's permission mode; set it to override. Run
                  models.list for allowed IDs. cwd is your project; no attachments.
  notes.list     {"limit":30,"offset":0}  Titles and short previews only.
  notes.read     {"id":"..."}  Full body of one note.
  notes.write    {"title":"Plan","body":"Markdown","tags":["work"]}
                  Create a note linked to this session and project. Omit title
                  to derive it from the body. Use {"id":"...","body":"..."}
                  to edit an existing note; title and tags are also optional.
                  Omitted fields stay unchanged. Reuse --request-id on retries.
An agent's sessions.* actions work in its workdir; "project" may name it and
is otherwise left out. Ordinary sessions cannot pass it.
  sessions.stop    {"sessionId":"..."}  Cancel another session's current turn.
  sessions.archive {"sessionId":"..."}  Stop it and put it away; it can be restored.
  sessions.delete  {"sessionId":"..."}  Remove it for good. The user is asked to
                  confirm first; the call fails if they decline.
                  None of these can target the caller, an agent's chat or its heartbeat's run.
  In an agent's chat, sessions.start reports the session's result back when it
  stops; pass "notifyOnComplete":false to opt out, or "notifyOnComplete":true
  on sessions.send to hear back about a follow-up.

Only in an agent's own conversation:
  agent.rename   {"name":"Scout","role":"CI watcher"}  Change its name and role.
  soul.read      {}  Its standing instructions (SOUL.md) and their hash.
  soul.update    {"text":"<complete Markdown>","expectedHash":"<from soul.read>"}
                  Replace them. A stale expectedHash is rejected.
  memory.add     {"fact":"...","until":"YYYY-MM-DD","topic":"<name>"}
                  Remember one dated fact; until and topic are optional.
  memory.replace {"find":"<text of the old entry>","fact":"..."}
                  Supersede an entry that changed.
  memory.remove  {"find":"..."}  Drop an entry that was wrong.
  memory.read    {"topic":"<name>"}  One topic file, or MEMORY.md without topic.
  memory.search  {"query":"...","since":"7d"}  Search memory, topic notes and
                  the archive. since is a date or a span like 24h, 7d, 2w.
  documents.list {}  The documents in its library, newest first, each with its
                  kind: "source" (first-hand, lists its sourceUrl) or "guide"
                  (one it wrote itself). A PDF source also lists its pdf path
                  and page count.
  documents.read {"id":"pods"}  One of them, in full, to revise or build on.
                  A PDF source comes back with pages: [{page,text}], so a
                  claim can cite a real page.
  documents.write {"id":"k8s-pod-lifecycle","title":"Pod Lifecycle",
                  "subject":"Kubernetes","path":"/abs/path/pod-lifecycle.md",
                  "sourceUrl":"https://kubernetes.io/docs/...","version":"v1.34"}
                  Take a source into the library: the text someone else
                  published, read from the UTF-8 Markdown file at path exactly
                  as saved, so it never passes through a reply. sourceUrl is
                  where it was published; subject and version are optional.
                  Absolute https image URLs are rendered directly.
                  A PDF (a paper, a spec) is taken in the same way: give its
                  path and Loci copies it in, reads its text for search, and
                  the user reads it in the PDF reader. Cite it by page,
                  loci://source/<id>#p7 (quote is optional).
                  A source cannot be revised by a document block; the
                  same id here takes the file in again. At most 1 MB of
                  Markdown, or 100 MB of PDF.
                  Only what someone else published is a source; never save
                  your own summary or notes here.
  documents.translate {"id":"k8s-pod-lifecycle","section":"Pod phase",
                  "path":"/abs/path/pod-phase.zh-CN.md"}
                  Translate a source, or one section of it, into the user's
                  learning language (or "language"), so they can read it in
                  that language beside the original. Give the section's whole
                  Markdown, translated, as path or "body": the same headings at
                  the same levels, code exactly as it was. The source itself is
                  never changed and stays what you cite and quote. Without
                  section, the whole document. Translate the sections your
                  lessons open, a lesson or two ahead; documents.read shows
                  which are done and which are out of date.
  guides.write   {"id":"k8s-reading-guide","title":"How to read the scheduler docs",
                  "subject":"Kubernetes","path":"/abs/path/guide.md"}
                  Save a guide you wrote yourself (a reading guide, a brief, a
                  map of the material): from the Markdown file at path, or
                  given as "body". It has no sourceUrl and the user sees it
                  labelled as your guide, apart from first-hand sources. The
                  same id revises it. A guide and a source never share an id.
  courses.list   {}  Its courses, newest first, with how many lessons the user
                  has read of each.
  courses.read   {"id":"k8s-reading"}  One course in full, with progress per
                  lesson id: untouched, learning (opened) or mastered (read).
                  Lessons with their own text say text:true; lessons with
                  only a title say planned:true.
  courses.write  {"id":"k8s-reading","title":"Kubernetes reading",
                  "chapters":[{"title":"Workloads","lessons":[...]}]}
                  Save a course to its library; it appears in Loci's Courses
                  at once. The fields are a loci-course block's front matter
                  and JSON body in one object (see Reading course below).
                  A lesson's text goes in the lesson as "body" (Markdown) or
                  "bodyPath" (an absolute .md file) and is kept in its own
                  file. The same id replaces the course and keeps progress for
                  lesson ids that remain; a lesson left out loses its text.
  courses.delete {"id":"k8s-reading"}  Remove a course, its lesson texts and progress.
  lessons.read   {"course":"k8s-reading","lesson":"pods"}  One lesson's text.
  lessons.write  {"course":"k8s-reading","lesson":"pods","path":"/abs/pods.md"}
                  Write or revise one lesson's text ("path" or "body"),
                  leaving the rest of the course as it is.
  lessons.questions {"course":"k8s-reading","lesson":"pods"}  What the learner
                  asked while that lesson was open, oldest first. Leave out
                  lesson for a course, or both for every lesson.
  glossary.read  {}  The glossary: every term with its aliases, definition and
                  the lesson that teaches it.
  glossary.write {"terms":[{"term":"watch","aliases":["watches"],"definition":"A
                  client's subscription to changes of one kind of object.",
                  "course":"k8s-reading","lesson":"watch-and-list"}]}
                  Add terms, or replace those with the same name (any case).
  glossary.remove {"terms":["watch"]}  Take terms out by name.

The output is one JSON line: {"ok":true,"result":...} or {"ok":false,"error":"..."}.
Note results include a stable loci://note/ID url.
Successful writes include saved:true. Markdown [title](url) links open the
saved resource inside Loci; they do not open a browser or launch Loci from
another application.
--input - reads JSON from stdin. Access uses credentials supplied by Loci.
The same --request-id identifies retries after an uncertain result.
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

/// The command layer's commands a mentor's own turn may call (`reader.*`).
fn mentor_commands() -> Vec<crate::external_cli::CommandSpec> {
    crate::external_cli::manifest()
        .commands
        .into_iter()
        .filter(|command| command.callers.iter().any(|caller| caller == "agent"))
        .collect()
}

/// Their part of the help, written from the same definitions as the terminal's.
fn mentor_commands_help() -> String {
    let mut out = String::from(
        "\nAlso in an agent's own conversation (the mentor's reader beside the chat):\n",
    );
    for command in mentor_commands() {
        let fields: Vec<String> = command
            .fields
            .iter()
            .filter(|field| field.name != "mentor" && field.name != "switch")
            .map(|field| format!("\"{}\"", field.name))
            .collect();
        out.push_str(&format!(
            "  {:<14} {{{}}}\n                  {}\n",
            command.name,
            fields.join(","),
            command.summary
        ));
        for field in command
            .fields
            .iter()
            .filter(|field| field.name != "mentor" && field.name != "switch")
        {
            out.push_str(&format!(
                "                  {}: {}\n",
                field.name, field.help
            ));
        }
    }
    out
}

pub fn app_help() -> String {
    let exe = std::env::current_exe()
        .map(|path| quoted(&path.to_string_lossy()))
        .unwrap_or_else(|_| "loci".into());
    format!(
        "{}{}\n{}",
        APP_USAGE.replace("{exe}", &exe),
        mentor_commands_help(),
        include_str!("../resources/app-formats.md")
    )
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
    let mentor_actions = mentor_commands();
    if !APP_ACTIONS.contains(&action.as_str())
        && !mentor_actions.iter().any(|command| command.name == action)
    {
        let mut all: Vec<&str> = APP_ACTIONS.to_vec();
        all.extend(mentor_actions.iter().map(|command| command.name.as_str()));
        return Err(format!(
            "Unknown action: {action}. Use one of: {}. Run app --help.",
            all.join(", ")
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
        for action in ["reader.open", "reader.show", "reader.close"] {
            assert!(text.contains(action), "help omits {action}");
            assert!(parse_args(&args(&[action])).is_ok());
        }
        assert!(!text.contains("{exe}"));
        assert!(text.contains("--request-id"));
        for fence in [
            "loci-question",
            "loci-document",
            "loci-todo",
            "loci-mindmap",
            "loci-course",
            "loci-diff",
        ] {
            assert!(text.contains(fence), "help omits format {fence}");
        }
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
