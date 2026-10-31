//! `loci <noun> <verb>`: Loci's command line for terminals outside the app.
//!
//! The commands are defined in the app (`src/app/commands`) and described in
//! `resources/cli-commands.json`, which this client reads to parse arguments
//! and print help. A call reads the running app's endpoint and local token
//! from that build's data folder, sends one JSON line on loopback and prints
//! the JSON answer. Every build has its own identifier and data folder:
//! `--app` chooses which Loci to talk to, and the default is the build this
//! executable is.
use std::collections::BTreeMap;
use std::io::{BufRead, BufReader, IsTerminal, Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::path::Path;
use std::time::{Duration, Instant};

use serde::Deserialize;
use serde_json::{json, Map, Value};

use crate::cli_access;

const MANIFEST: &str = include_str!("../resources/cli-commands.json");
const INPUT_MAX: usize = 262_144;
const RESPONSE_MAX: u64 = 4_000_000;
/// The app waits up to 120 s for a window; leave room for the answer.
const READ_TIMEOUT: Duration = Duration::from_secs(130);
const WAIT_DEFAULT: Duration = Duration::from_secs(900);
const POLL_EVERY: Duration = Duration::from_millis(500);
pub const APP_ID_ENV: &str = "LOCI_APP_ID";

#[derive(Debug, Clone, Deserialize)]
pub struct Manifest {
    pub commands: Vec<CommandSpec>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CommandSpec {
    pub name: String,
    pub summary: String,
    pub callers: Vec<String>,
    #[serde(default)]
    pub destructive: bool,
    pub fields: Vec<FieldSpec>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FieldSpec {
    pub name: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub help: String,
    #[serde(default)]
    pub required: bool,
    #[serde(default)]
    pub positional: bool,
}

pub fn manifest() -> Manifest {
    let mut manifest: Manifest =
        serde_json::from_str(MANIFEST).expect("resources/cli-commands.json is valid");
    // Answered by the app's host process itself, before any window.
    for (name, summary) in [
        (
            "status.show",
            "Whether this Loci is running, and its identifier and version.",
        ),
        (
            "cli.rotate-token",
            "Replace the local token; the old one stops working at once.",
        ),
        (
            "cli.disable",
            "Turn command-line access off. Turn it back on in Settings.",
        ),
    ] {
        manifest.commands.push(CommandSpec {
            name: name.into(),
            summary: summary.into(),
            callers: vec!["external".into()],
            destructive: false,
            fields: vec![],
        });
    }
    manifest
}

fn external_commands(manifest: &Manifest) -> BTreeMap<String, Vec<&CommandSpec>> {
    let mut nouns: BTreeMap<String, Vec<&CommandSpec>> = BTreeMap::new();
    for command in &manifest.commands {
        if !command.callers.iter().any(|caller| caller == "external") {
            continue;
        }
        let noun = command.name.split('.').next().unwrap_or_default();
        nouns.entry(noun.into()).or_default().push(command);
    }
    nouns
}

/// Whether these arguments are meant for this command line rather than the app.
pub fn handles(args: &[String]) -> bool {
    let mut rest = args.iter();
    while let Some(arg) = rest.next() {
        match arg.as_str() {
            "--app" => {
                rest.next();
            }
            value if value.starts_with("--app=") => {}
            "help" | "--help" | "-h" => return true,
            first => return external_commands(&manifest()).contains_key(first),
        }
    }
    false
}

/// What the user asked for.
#[derive(Debug, PartialEq)]
pub enum Invocation {
    Help(String),
    Call(Call),
}

#[derive(Debug, PartialEq)]
pub struct Call {
    pub app: Option<String>,
    pub action: String,
    pub input: Value,
    pub request_id: String,
    pub wait: Option<Wait>,
}

#[derive(Debug, PartialEq)]
pub struct Wait {
    pub timeout: Duration,
    pub stream: bool,
}

pub struct Failure {
    pub error: String,
    pub code: &'static str,
}

fn usage(error: impl Into<String>) -> Failure {
    Failure {
        error: error.into(),
        code: "usage",
    }
}

fn kebab(name: &str) -> String {
    let mut out = String::new();
    for c in name.chars() {
        if c.is_ascii_uppercase() {
            out.push('-');
            out.push(c.to_ascii_lowercase());
        } else {
            out.push(c);
        }
    }
    out
}

fn read_source(path: &str) -> Result<String, Failure> {
    let raw = if path == "-" {
        let mut raw = String::new();
        std::io::stdin()
            .take(INPUT_MAX as u64 + 1)
            .read_to_string(&mut raw)
            .map_err(|e| usage(e.to_string()))?;
        raw
    } else {
        let file = std::fs::File::open(path).map_err(|e| usage(format!("{path}: {e}")))?;
        let mut raw = String::new();
        file.take(INPUT_MAX as u64 + 1)
            .read_to_string(&mut raw)
            .map_err(|e| usage(format!("{path}: {e}")))?;
        raw
    };
    if raw.len() > INPUT_MAX {
        return Err(usage(format!("{path} is larger than 256 KiB")));
    }
    Ok(raw)
}

fn typed(field: &FieldSpec, raw: &str) -> Result<Value, Failure> {
    let flag = kebab(&field.name);
    match field.kind.as_str() {
        "integer" => raw
            .trim()
            .parse::<i64>()
            .map(Value::from)
            .map_err(|_| usage(format!("--{flag} must be an integer"))),
        "boolean" => match raw {
            "true" => Ok(Value::Bool(true)),
            "false" => Ok(Value::Bool(false)),
            _ => Err(usage(format!("--{flag} must be true or false"))),
        },
        "json" => {
            serde_json::from_str(raw).map_err(|e| usage(format!("--{flag} must be JSON: {e}")))
        }
        _ => Ok(Value::String(raw.into())),
    }
}

fn valid_request_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

/// `loci [--app ID] <noun> [<verb>] [arguments and options]`.
pub fn parse(manifest: &Manifest, args: &[String]) -> Result<Invocation, Failure> {
    let nouns = external_commands(manifest);
    let mut app = None;
    let mut help = false;
    let mut rest: Vec<String> = Vec::new();
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if arg == "--app" {
            app = Some(
                iter.next()
                    .cloned()
                    .ok_or_else(|| usage("--app needs an identifier"))?,
            );
        } else if let Some(value) = arg.strip_prefix("--app=") {
            app = Some(value.to_string());
        } else if arg == "--help" || arg == "-h" || (arg == "help" && rest.is_empty()) {
            help = true;
        } else {
            rest.push(arg.clone());
        }
    }
    let Some(noun) = rest.first().filter(|word| !word.starts_with("--")) else {
        if rest.is_empty() {
            return Ok(Invocation::Help(overview(manifest)));
        }
        return Err(usage(
            "Name a command first. Run `loci --help` for the list.",
        ));
    };
    let Some(commands) = nouns.get(noun.as_str()) else {
        return Err(usage(format!(
            "Unknown command: {noun}. Run `loci --help` for the list."
        )));
    };
    let named = rest.get(1).filter(|word| !word.starts_with("--"));
    let spec = match named {
        Some(verb) => match commands.iter().find(|c| verb_of(&c.name) == verb.as_str()) {
            Some(spec) => *spec,
            None if help => return Ok(Invocation::Help(noun_help(noun, commands))),
            None => {
                return Err(usage(format!(
                    "Unknown command: {noun} {verb}. Run `loci {noun} --help`."
                )))
            }
        },
        // `loci status` has one verb and no need to name it.
        None if commands.len() == 1 && commands[0].fields.is_empty() && !help => commands[0],
        None => return Ok(Invocation::Help(noun_help(noun, commands))),
    };
    if help {
        return Ok(Invocation::Help(command_help(spec)));
    }
    let skip = if named.is_some_and(|verb| verb_of(&spec.name) == verb.as_str()) {
        2
    } else {
        1
    };
    let waits = spec.name == "mentors.send";
    let mut input = Map::new();
    let mut base = Map::new();
    let mut words = Vec::new();
    let mut request_id = None;
    let mut wait = false;
    let mut stream = false;
    let mut timeout = None;
    let mut iter = rest[skip..].iter();
    while let Some(arg) = iter.next() {
        let Some(flag) = arg.strip_prefix("--") else {
            words.push(arg.clone());
            continue;
        };
        if flag.is_empty() {
            words.extend(iter.by_ref().cloned());
            break;
        }
        let (name, inline) = match flag.split_once('=') {
            Some((name, value)) => (name, Some(value.to_string())),
            None => (flag, None),
        };
        let mut value = |what: &str| -> Result<String, Failure> {
            inline
                .clone()
                .or_else(|| iter.next().cloned())
                .ok_or_else(|| usage(format!("--{name} needs {what}")))
        };
        match name {
            "json" => continue,
            "request-id" => {
                let id = value("a value")?;
                if !valid_request_id(&id) {
                    return Err(usage(
                        "--request-id uses letters, digits, underscores and hyphens (at most 128)",
                    ));
                }
                request_id = Some(id);
                continue;
            }
            "input" => {
                match serde_json::from_str::<Value>(&read_source(&value("a file or -")?)?) {
                    Ok(Value::Object(object)) => base = object,
                    _ => return Err(usage("--input must hold one JSON object")),
                }
                continue;
            }
            "wait" if waits => {
                wait = true;
                continue;
            }
            "stream" if waits => {
                stream = true;
                continue;
            }
            "timeout" if waits => {
                let seconds = value("seconds")?
                    .parse::<u64>()
                    .ok()
                    .filter(|s| *s > 0)
                    .ok_or_else(|| usage("--timeout takes seconds"))?;
                timeout = Some(Duration::from_secs(seconds));
                continue;
            }
            _ => {}
        }
        let find = |name: &str| spec.fields.iter().find(|f| kebab(&f.name) == name);
        let unknown = || {
            usage(format!(
                "Unknown option --{name} for `loci {}`. Run it with --help.",
                spec.name.replace('.', " ")
            ))
        };
        if let Some(field) = find(name) {
            let parsed = if field.kind == "boolean" {
                match inline.as_deref() {
                    None => Value::Bool(true),
                    Some(raw) => typed(field, raw)?,
                }
            } else {
                typed(field, &value("a value")?)?
            };
            input.insert(field.name.clone(), parsed);
        } else if let Some(field) = name
            .strip_prefix("no-")
            .and_then(find)
            .filter(|f| f.kind == "boolean")
        {
            input.insert(field.name.clone(), Value::Bool(false));
        } else if let Some(field) = name
            .strip_suffix("-file")
            .and_then(find)
            .filter(|f| f.kind != "boolean")
        {
            let text = read_source(&value("a file or -")?)?;
            let parsed = if field.kind == "string" {
                Value::String(text)
            } else {
                typed(field, text.trim())?
            };
            input.insert(field.name.clone(), parsed);
        } else {
            return Err(unknown());
        }
    }
    let mut slots = spec.fields.iter().filter(|f| f.positional);
    for word in words {
        let Some(field) = slots.find(|f| !input.contains_key(&f.name)) else {
            return Err(usage(format!(
                "Unexpected argument: {word}. Run `loci {} --help`.",
                spec.name.replace('.', " ")
            )));
        };
        input.insert(field.name.clone(), typed(field, &word)?);
    }
    base.extend(input);
    if let Some(missing) = spec
        .fields
        .iter()
        .find(|f| f.required && !base.contains_key(&f.name))
    {
        let shown = if missing.positional {
            format!("<{}>", kebab(&missing.name))
        } else {
            format!("--{}", kebab(&missing.name))
        };
        return Err(usage(format!(
            "{shown} is required. Run `loci {} --help`.",
            spec.name.replace('.', " ")
        )));
    }
    let wait = (wait || stream || timeout.is_some()).then(|| Wait {
        timeout: timeout.unwrap_or(WAIT_DEFAULT),
        stream,
    });
    let action = match spec.name.as_str() {
        "status.show" => "status".to_string(),
        name => name.to_string(),
    };
    Ok(Invocation::Call(Call {
        app,
        action,
        input: Value::Object(base),
        request_id: request_id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string()),
        wait,
    }))
}

fn verb_of(name: &str) -> &str {
    name.split_once('.').map_or(name, |(_, verb)| verb)
}

const GLOBAL_HELP: &str = "Options for every command:
  --app ID          Which Loci to talk to, by identifier (or LOCI_APP_ID).
                    Default: the build this executable is ({default}).
  --input FILE|-    Take the fields from a JSON object; options override it.
  --request-id ID   Name this call so a retry is not done twice.
  --<field>-file F  Read a field's value from a file (- for stdin).
  --json            Accepted; output is always JSON.

Output is one JSON object: {\"ok\":true,\"result\":...} or
{\"ok\":false,\"error\":\"...\",\"code\":\"...\"}.
Exit status: 0 ok, 1 refused, 2 usage, 3 Loci not running, 4 access off or
bad token, 5 timed out, 6 declined or waiting for you.";

fn global_help() -> String {
    GLOBAL_HELP.replace("{default}", &crate::built_identifier())
}

fn overview(manifest: &Manifest) -> String {
    let mut out = String::from(
        "loci — drive a running Loci from the command line.\n\nUsage: loci <command> <verb> [arguments] [options]\n\nCommands:\n",
    );
    for (noun, commands) in external_commands(manifest) {
        let verbs: Vec<&str> = commands.iter().map(|c| verb_of(&c.name)).collect();
        out.push_str(&format!("  {noun:<11} {}\n", verbs.join(", ")));
    }
    out.push_str("\nRun `loci <command> --help` for its verbs and `loci <command> <verb> --help` for its options.\n\n");
    out.push_str(&global_help());
    out
}

fn noun_help(noun: &str, commands: &[&CommandSpec]) -> String {
    let mut out = format!("Usage: loci {noun} <verb> [arguments] [options]\n\nVerbs:\n");
    for command in commands {
        out.push_str(&format!(
            "  {:<12} {}\n",
            verb_of(&command.name),
            command.summary
        ));
    }
    out.push('\n');
    out.push_str(&global_help());
    out
}

fn command_help(spec: &CommandSpec) -> String {
    let mut usage_line = format!("Usage: loci {}", spec.name.replace('.', " "));
    for field in spec.fields.iter().filter(|f| f.positional) {
        if field.required {
            usage_line.push_str(&format!(" <{}>", kebab(&field.name)));
        } else {
            usage_line.push_str(&format!(" [{}]", kebab(&field.name)));
        }
    }
    usage_line.push_str(" [options]");
    let mut out = format!("{usage_line}\n\n{}\n", spec.summary);
    if !spec.fields.is_empty() {
        out.push_str("\nFields:\n");
        for field in &spec.fields {
            let name = if field.positional {
                format!("<{}>", kebab(&field.name))
            } else if field.kind == "boolean" {
                format!("--{}", kebab(&field.name))
            } else {
                format!("--{} <{}>", kebab(&field.name), field.kind)
            };
            let required = if field.required { " (required)" } else { "" };
            out.push_str(&format!("  {name:<24} {}{required}\n", field.help));
        }
    }
    if spec.name == "mentors.send" {
        out.push_str(
            "  --wait                   Wait for the reply and print it.\n  --stream                 With --wait, print the reply as it grows (one JSON line each).\n  --timeout <seconds>      How long --wait waits (default 900).\n",
        );
    }
    if spec.destructive {
        out.push_str("\nThis cannot be undone. Loci asks you to confirm; Loci Dev and QA builds skip the question with --yes.\n");
    }
    out.push('\n');
    out.push_str(&global_help());
    out
}

pub fn exit_code(code: Option<&str>) -> i32 {
    match code {
        None => 1,
        Some("usage") => 2,
        Some("not_running") => 3,
        Some("unauthorized" | "disabled") => 4,
        Some("timeout") => 5,
        Some("declined" | "needs_you") => 6,
        Some(_) => 1,
    }
}

fn failure_value(failure: &Failure) -> Value {
    json!({"ok": false, "error": failure.error, "code": failure.code})
}

fn print(value: &Value, pretty: bool) {
    let text = if pretty {
        serde_json::to_string_pretty(value).unwrap_or_default()
    } else {
        value.to_string()
    };
    println!("{text}");
}

fn outcome(value: &Value) -> i32 {
    if value.get("ok").and_then(Value::as_bool) == Some(true) {
        0
    } else {
        exit_code(Some(
            value
                .get("code")
                .and_then(Value::as_str)
                .unwrap_or("failed"),
        ))
    }
}

/// The identifier of the Loci to talk to.
pub fn target(app: Option<String>) -> Result<String, Failure> {
    let identifier = app
        .or_else(|| {
            std::env::var(APP_ID_ENV)
                .ok()
                .filter(|v| !v.trim().is_empty())
        })
        .map(|v| v.trim().to_string())
        .unwrap_or_else(crate::built_identifier);
    if !cli_access::valid_identifier(&identifier) {
        return Err(usage(format!(
            "Not a Loci identifier: {identifier} (expected com.loci.…)"
        )));
    }
    Ok(identifier)
}

/// Sends one request to the Loci whose control files are in `dir`.
pub fn call_in(
    dir: &Path,
    action: &str,
    input: &Value,
    request_id: &str,
) -> Result<Value, Failure> {
    let endpoint = cli_access::read_endpoint(dir).map_err(|_| Failure {
        error: "Loci is not running (no endpoint). Start it, or choose another with --app.".into(),
        code: "not_running",
    })?;
    let token = cli_access::read_token(dir).map_err(|error| Failure {
        error: format!(
            "No usable Loci token ({error}). Command-line access may be off: turn it on in Settings → General → Command line."
        ),
        code: "unauthorized",
    })?;
    let address: SocketAddr = endpoint.endpoint.parse().map_err(|_| Failure {
        error: "The endpoint file is damaged".into(),
        code: "not_running",
    })?;
    if !address.ip().is_loopback() {
        return Err(Failure {
            error: "Loci control only connects to localhost".into(),
            code: "failed",
        });
    }
    let mut stream =
        TcpStream::connect_timeout(&address, Duration::from_secs(3)).map_err(|error| Failure {
            error: format!("Loci is not running at {address} ({error}). Start it, or choose another with --app."),
            code: "not_running",
        })?;
    let sent = |error: String| Failure {
        error: format!("{error}. The command may have run; retry with --request-id {request_id}."),
        code: "timeout",
    };
    stream
        .set_read_timeout(Some(READ_TIMEOUT))
        .and_then(|_| stream.set_write_timeout(Some(Duration::from_secs(5))))
        .map_err(|e| sent(e.to_string()))?;
    writeln!(
        stream,
        "{}",
        json!({"token": token, "namespace": "cli", "action": action, "input": input, "requestId": request_id})
    )
    .map_err(|e| sent(e.to_string()))?;
    let mut line = String::new();
    BufReader::new(stream)
        .take(RESPONSE_MAX + 1)
        .read_line(&mut line)
        .map_err(|e| sent(format!("No answer from Loci: {e}")))?;
    if line.len() as u64 > RESPONSE_MAX {
        return Err(sent("Loci's answer is too large".into()));
    }
    serde_json::from_str(&line).map_err(|_| sent("Loci returned an invalid answer".into()))
}

fn call(identifier: &str, action: &str, input: &Value, request_id: &str) -> Value {
    let dir = match cli_access::app_data_dir(identifier) {
        Ok(dir) => cli_access::control_dir(&dir),
        Err(error) => return failure_value(&usage(error)),
    };
    call_in(&dir, action, input, request_id).unwrap_or_else(|failure| failure_value(&failure))
}

/// Polls the turn `send` started until it settles, printing it as it grows when streaming.
fn wait_for_turn(
    identifier: &str,
    sent: &Value,
    wait: &Wait,
    mut emit: impl FnMut(&Value),
) -> Value {
    let result = &sent["result"];
    let (Some(mentor), Some(turn)) = (result["mentor"].as_str(), result["turn"].as_str()) else {
        return json!({"ok": false, "error": "Loci did not say which turn it started", "code": "failed"});
    };
    let started = Instant::now();
    let mut shown = String::new();
    loop {
        let value = call(
            identifier,
            "mentors.turn",
            &json!({"mentor": mentor, "turn": turn}),
            &uuid::Uuid::new_v4().to_string(),
        );
        if value["ok"].as_bool() != Some(true) {
            return value;
        }
        let state = &value["result"];
        if wait.stream {
            let text = state["text"].as_str().unwrap_or_default();
            if text != shown {
                if let Some(delta) = text.strip_prefix(shown.as_str()) {
                    emit(&json!({"type": "delta", "text": delta}));
                } else {
                    emit(&json!({"type": "replace", "text": text}));
                }
                shown = text.into();
            }
        }
        match state["status"].as_str() {
            Some("done") => return value,
            Some("needs-you") => {
                return json!({"ok": false, "error": "The mentor is waiting for you in Loci (an approval or a question).", "code": "needs_you", "result": state})
            }
            Some("failed" | "stopped") => {
                return json!({"ok": false, "error": state["error"].as_str().unwrap_or("The turn did not finish"), "code": "failed", "result": state})
            }
            _ => {}
        }
        if started.elapsed() >= wait.timeout {
            return json!({"ok": false, "error": "The mentor is still working; read the reply later with `loci mentors turn`.", "code": "timeout", "result": state});
        }
        std::thread::sleep(POLL_EVERY);
    }
}

pub fn run(args: Vec<String>) -> i32 {
    let manifest = manifest();
    let pretty = std::io::stdout().is_terminal();
    let call_spec = match parse(&manifest, &args) {
        Ok(Invocation::Help(text)) => {
            println!("{text}");
            return 0;
        }
        Ok(Invocation::Call(call)) => call,
        Err(failure) => {
            print(&failure_value(&failure), pretty);
            return exit_code(Some(failure.code));
        }
    };
    let identifier = match target(call_spec.app.clone()) {
        Ok(identifier) => identifier,
        Err(failure) => {
            print(&failure_value(&failure), pretty);
            return exit_code(Some(failure.code));
        }
    };
    let value = call(
        &identifier,
        &call_spec.action,
        &call_spec.input,
        &call_spec.request_id,
    );
    let value = match (&call_spec.wait, value["ok"].as_bool()) {
        (Some(wait), Some(true)) => {
            let value = wait_for_turn(&identifier, &value, wait, |line| print(line, false));
            if wait.stream {
                print(&json!({"type": "done", "response": value}), false);
                return outcome(&value);
            }
            value
        }
        _ => value,
    };
    print(&value, pretty);
    outcome(&value)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;

    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(|v| v.to_string()).collect()
    }

    fn test_manifest() -> Manifest {
        let mut manifest = manifest();
        manifest.commands.push(serde_json::from_value(json!({
            "name": "things.make", "summary": "Make a thing.", "callers": ["external"], "destructive": true,
            "fields": [
                {"name": "mentor", "type": "string", "help": "Mentor", "required": true, "positional": true},
                {"name": "text", "type": "string", "help": "Text", "required": false, "positional": true},
                {"name": "maxChars", "type": "integer", "help": "Cap", "required": false, "positional": false},
                {"name": "yes", "type": "boolean", "help": "Confirm", "required": false, "positional": false},
                {"name": "chapters", "type": "json", "help": "Body", "required": false, "positional": false}
            ]
        })).unwrap());
        manifest.commands.push(serde_json::from_value(json!({
            "name": "things.secret", "summary": "Agents only.", "callers": ["agent"], "fields": []
        })).unwrap());
        manifest
    }

    fn call_of(values: &[&str]) -> Call {
        match parse(&test_manifest(), &args(values)) {
            Ok(Invocation::Call(call)) => call,
            Ok(Invocation::Help(text)) => panic!("help: {text}"),
            Err(failure) => panic!("{}: {}", failure.code, failure.error),
        }
    }

    fn error_of(values: &[&str]) -> String {
        match parse(&test_manifest(), &args(values)) {
            Err(failure) => {
                assert_eq!(failure.code, "usage");
                failure.error
            }
            _ => panic!("expected a usage error"),
        }
    }

    #[test]
    fn the_manifest_parses_and_names_only_its_own_nouns() {
        let manifest = manifest();
        assert!(manifest.commands.iter().any(|c| c.name == "templates.list"));
        assert!(handles(&args(&["status"])));
        assert!(handles(&args(&[
            "--app",
            "com.loci.desktop.qa",
            "templates",
            "list"
        ])));
        assert!(handles(&args(&["--help"])));
        // The agents' own command lines and the app's start are left alone.
        assert!(!handles(&args(&["app", "notes.list"])));
        assert!(!handles(&args(&["canvas", "create_view"])));
        assert!(!handles(&args(&[])));
    }

    #[test]
    fn fields_come_from_positionals_options_and_files() {
        let call = call_of(&[
            "things",
            "make",
            "m1",
            "hello world",
            "--max-chars",
            "40",
            "--yes",
            "--chapters",
            "[1]",
            "--app",
            "com.loci.desktop.qa",
        ]);
        assert_eq!(call.action, "things.make");
        assert_eq!(call.app.as_deref(), Some("com.loci.desktop.qa"));
        assert_eq!(
            call.input,
            json!({"mentor": "m1", "text": "hello world", "maxChars": 40, "yes": true, "chapters": [1]})
        );
        // A switch does not swallow the word after it.
        let call = call_of(&["things", "make", "--yes", "m1"]);
        assert_eq!(call.input, json!({"mentor": "m1", "yes": true}));
        let call = call_of(&["things", "make", "m1", "--no-yes", "--max-chars=3"]);
        assert_eq!(
            call.input,
            json!({"mentor": "m1", "yes": false, "maxChars": 3})
        );
        let dir = std::env::temp_dir().join(format!("loci-cli-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let text = dir.join("text.md");
        std::fs::write(&text, "# From a file\n").unwrap();
        let base = dir.join("input.json");
        std::fs::write(&base, r#"{"mentor":"from-input","maxChars":1}"#).unwrap();
        let call = call_of(&[
            "things",
            "make",
            "--text-file",
            text.to_str().unwrap(),
            "--input",
            base.to_str().unwrap(),
            "--max-chars",
            "2",
        ]);
        assert_eq!(
            call.input,
            json!({"mentor": "from-input", "text": "# From a file\n", "maxChars": 2})
        );
    }

    #[test]
    fn mistakes_are_usage_errors() {
        assert!(error_of(&["nothing", "here"]).contains("Unknown command: nothing"));
        assert!(error_of(&["things", "fly"]).contains("Unknown command: things fly"));
        assert!(error_of(&["things", "make"]).contains("<mentor> is required"));
        assert!(
            error_of(&["things", "make", "m", "t", "extra"]).contains("Unexpected argument: extra")
        );
        assert!(
            error_of(&["things", "make", "m", "--max-chars", "x"]).contains("must be an integer")
        );
        assert!(error_of(&["things", "make", "m", "--chapters", "{"]).contains("must be JSON"));
        assert!(
            error_of(&["things", "make", "m", "--color", "red"]).contains("Unknown option --color")
        );
        assert!(error_of(&["things", "make", "m", "--request-id", "a/b"]).contains("--request-id"));
        assert!(error_of(&["things", "make", "m", "--wait"]).contains("Unknown option --wait"));
        // Agent-only commands are not offered to terminals.
        assert!(error_of(&["things", "secret"]).contains("Unknown command: things secret"));
    }

    #[test]
    fn help_is_offered_at_every_level() {
        let help = |values: &[&str]| match parse(&test_manifest(), &args(values)) {
            Ok(Invocation::Help(text)) => text,
            _ => panic!("expected help"),
        };
        assert!(help(&[]).contains("things"));
        assert!(help(&["--help"]).contains("Exit status"));
        assert!(help(&["things"]).contains("make"));
        assert!(help(&["things", "--help"]).contains("Make a thing."));
        let command = help(&["things", "make", "--help"]);
        assert!(command.contains("Usage: loci things make <mentor> [text]"));
        assert!(command.contains("--max-chars <integer>"));
        assert!(command.contains("cannot be undone"));
    }

    #[test]
    fn host_commands_and_waiting_parse() {
        let call = call_of(&["status"]);
        assert_eq!(call.action, "status");
        assert_eq!(call_of(&["cli", "rotate-token"]).action, "cli.rotate-token");
        let mut manifest = test_manifest();
        manifest.commands.push(serde_json::from_value(json!({
            "name": "mentors.send", "summary": "Send.", "callers": ["external"],
            "fields": [{"name": "mentor", "type": "string", "help": "", "required": true, "positional": true},
                       {"name": "text", "type": "string", "help": "", "required": true, "positional": true}]
        })).unwrap());
        let Ok(Invocation::Call(call)) = parse(
            &manifest,
            &args(&[
                "mentors",
                "send",
                "m",
                "hi",
                "--wait",
                "--timeout",
                "60",
                "--stream",
            ]),
        ) else {
            panic!("expected a call");
        };
        assert_eq!(
            call.wait,
            Some(Wait {
                timeout: Duration::from_secs(60),
                stream: true
            })
        );
        assert_eq!(call.input, json!({"mentor": "m", "text": "hi"}));
    }

    #[test]
    fn exit_codes_are_stable() {
        assert_eq!(exit_code(Some("usage")), 2);
        assert_eq!(exit_code(Some("not_running")), 3);
        assert_eq!(exit_code(Some("disabled")), 4);
        assert_eq!(exit_code(Some("unauthorized")), 4);
        assert_eq!(exit_code(Some("timeout")), 5);
        assert_eq!(exit_code(Some("declined")), 6);
        assert_eq!(exit_code(Some("needs_you")), 6);
        assert_eq!(exit_code(Some("not_found")), 1);
        assert_eq!(outcome(&json!({"ok": true})), 0);
        assert_eq!(outcome(&json!({"ok": false, "code": "busy"})), 1);
    }

    #[test]
    fn the_target_is_an_identifier_never_a_path() {
        assert_eq!(
            target(Some("com.loci.desktop.qa".into())).ok(),
            Some("com.loci.desktop.qa".into())
        );
        assert!(target(Some("../../etc".into())).is_err());
        // Without --app, this executable's own build.
        if std::env::var(APP_ID_ENV).is_err() {
            assert_eq!(target(None).ok(), Some(crate::built_identifier()));
        }
    }

    #[test]
    fn a_call_reads_the_endpoint_and_token_and_speaks_one_line() {
        let dir = std::env::temp_dir().join(format!("loci-cli-call-{}", uuid::Uuid::new_v4()));
        assert_eq!(
            call_in(&dir, "templates.list", &json!({}), "r1")
                .err()
                .map(|f| f.code),
            Some("not_running")
        );
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap().to_string();
        cli_access::write_endpoint(
            &dir,
            &cli_access::Endpoint {
                endpoint: address,
                pid: 1,
                version: "0".into(),
                identifier: "com.loci.desktop.test".into(),
            },
        )
        .unwrap();
        assert_eq!(
            call_in(&dir, "templates.list", &json!({}), "r1")
                .err()
                .map(|f| f.code),
            Some("unauthorized")
        );
        let token = cli_access::ensure_token(&dir).unwrap();
        let server = std::thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            let mut line = String::new();
            BufReader::new(&stream).read_line(&mut line).unwrap();
            let request: Value = serde_json::from_str(&line).unwrap();
            writeln!(
                &stream,
                "{}",
                json!({"ok": true, "result": {"echo": request["action"]}})
            )
            .unwrap();
            request
        });
        let value = call_in(&dir, "templates.list", &json!({"a": 1}), "r1")
            .ok()
            .unwrap();
        assert_eq!(
            value,
            json!({"ok": true, "result": {"echo": "templates.list"}})
        );
        let request = server.join().unwrap();
        assert_eq!(request["token"], json!(token));
        assert_eq!(request["namespace"], "cli");
        assert_eq!(request["input"], json!({"a": 1}));
        assert_eq!(request["requestId"], "r1");
    }
}
