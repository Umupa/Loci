//! The languages the code reader understands, with tree-sitter: a file's
//! symbols (definitions, nested by range), the identifier at a place, and
//! where a name occurs. Name-based, like GitHub's code navigation; no LSP.

use std::collections::HashMap;
use std::sync::OnceLock;

use serde::Serialize;
use tree_sitter::{Language, Node, Parser, Point, Query, QueryCursor, StreamingIterator, Tree};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Lang {
    Go,
    Rust,
    C,
    TypeScript,
    Tsx,
    JavaScript,
    Python,
}

pub const ALL: [Lang; 7] = [
    Lang::Go,
    Lang::Rust,
    Lang::C,
    Lang::TypeScript,
    Lang::Tsx,
    Lang::JavaScript,
    Lang::Python,
];

impl Lang {
    /// The language of a file, by its extension.
    pub fn of(path: &str) -> Option<Lang> {
        let name = path.rsplit(['/', '\\']).next().unwrap_or(path);
        let ext = name.rsplit_once('.')?.1.to_ascii_lowercase();
        Some(match ext.as_str() {
            "go" => Lang::Go,
            "rs" => Lang::Rust,
            "c" | "h" => Lang::C,
            "ts" | "mts" | "cts" => Lang::TypeScript,
            "tsx" => Lang::Tsx,
            "js" | "mjs" | "cjs" | "jsx" => Lang::JavaScript,
            "py" | "pyi" => Lang::Python,
            _ => return None,
        })
    }

    pub fn id(self) -> &'static str {
        match self {
            Lang::Go => "go",
            Lang::Rust => "rust",
            Lang::C => "c",
            Lang::TypeScript => "typescript",
            Lang::Tsx => "tsx",
            Lang::JavaScript => "javascript",
            Lang::Python => "python",
        }
    }

    /// Files a name defined in this language can be used from.
    pub fn family_globs(self) -> &'static [&'static str] {
        match self {
            Lang::Go => &["*.go"],
            Lang::Rust => &["*.rs"],
            Lang::C => &["*.c", "*.h"],
            Lang::TypeScript | Lang::Tsx | Lang::JavaScript => &[
                "*.ts", "*.mts", "*.cts", "*.tsx", "*.js", "*.mjs", "*.cjs", "*.jsx",
            ],
            Lang::Python => &["*.py", "*.pyi"],
        }
    }

    fn language(self) -> Language {
        match self {
            Lang::Go => tree_sitter_go::LANGUAGE.into(),
            Lang::Rust => tree_sitter_rust::LANGUAGE.into(),
            Lang::C => tree_sitter_c::LANGUAGE.into(),
            Lang::TypeScript => tree_sitter_typescript::LANGUAGE_TYPESCRIPT.into(),
            Lang::Tsx => tree_sitter_typescript::LANGUAGE_TSX.into(),
            Lang::JavaScript => tree_sitter_javascript::LANGUAGE.into(),
            Lang::Python => tree_sitter_python::LANGUAGE.into(),
        }
    }

    fn definitions_query(self) -> &'static str {
        match self {
            Lang::Go => GO,
            Lang::Rust => RUST,
            Lang::C => C,
            Lang::TypeScript | Lang::Tsx => TYPESCRIPT,
            Lang::JavaScript => JAVASCRIPT,
            Lang::Python => PYTHON,
        }
    }

    fn query(self) -> &'static Query {
        static QUERIES: OnceLock<HashMap<Lang, Query>> = OnceLock::new();
        let all = QUERIES.get_or_init(|| {
            ALL.iter()
                .map(|lang| {
                    let query = Query::new(&lang.language(), lang.definitions_query())
                        .unwrap_or_else(|e| panic!("{} definitions query: {e}", lang.id()));
                    (*lang, query)
                })
                .collect()
        });
        &all[&self]
    }
}

// Each pattern captures the definition's name as @name and the whole
// definition as @definition.<kind>. When patterns overlap on one name, the
// first one listed wins, so the specific ones come first.

const GO: &str = r#"
(function_declaration name: (identifier) @name) @definition.function
(method_declaration name: (field_identifier) @name) @definition.method
(type_spec name: (type_identifier) @name type: (struct_type)) @definition.struct
(type_spec name: (type_identifier) @name type: (interface_type)) @definition.interface
(type_spec name: (type_identifier) @name) @definition.type
(type_alias name: (type_identifier) @name) @definition.type
(method_elem name: (field_identifier) @name) @definition.method
(field_declaration name: (field_identifier) @name) @definition.field
(source_file (const_declaration (const_spec name: (identifier) @name) @definition.constant))
(source_file (var_declaration (var_spec name: (identifier) @name) @definition.variable))
(source_file (var_declaration (var_spec_list (var_spec name: (identifier) @name) @definition.variable)))
"#;

const RUST: &str = r#"
(struct_item name: (type_identifier) @name) @definition.struct
(enum_item name: (type_identifier) @name) @definition.enum
(union_item name: (type_identifier) @name) @definition.struct
(type_item name: (type_identifier) @name) @definition.type
(trait_item name: (type_identifier) @name) @definition.interface
(impl_item type: (_) @name) @definition.impl
(impl_item body: (declaration_list (function_item name: (identifier) @name) @definition.method))
(trait_item body: (declaration_list (function_item name: (identifier) @name) @definition.method))
(function_item name: (identifier) @name) @definition.function
(function_signature_item name: (identifier) @name) @definition.method
(mod_item name: (identifier) @name) @definition.module
(macro_definition name: (identifier) @name) @definition.macro
(const_item name: (identifier) @name) @definition.constant
(static_item name: (identifier) @name) @definition.variable
(field_declaration name: (field_identifier) @name) @definition.field
(enum_variant name: (identifier) @name) @definition.enumMember
"#;

const C: &str = r#"
(function_definition declarator: (function_declarator declarator: (identifier) @name)) @definition.function
(function_definition declarator: (pointer_declarator declarator: (function_declarator declarator: (identifier) @name))) @definition.function
(function_definition declarator: (pointer_declarator declarator: (pointer_declarator declarator: (function_declarator declarator: (identifier) @name)))) @definition.function
(declaration declarator: (function_declarator declarator: (identifier) @name)) @definition.prototype
(declaration declarator: (pointer_declarator declarator: (function_declarator declarator: (identifier) @name))) @definition.prototype
(struct_specifier name: (type_identifier) @name body: (_)) @definition.struct
(union_specifier name: (type_identifier) @name body: (_)) @definition.struct
(enum_specifier name: (type_identifier) @name body: (_)) @definition.enum
(type_definition declarator: (type_identifier) @name) @definition.type
(type_definition declarator: (pointer_declarator declarator: (type_identifier) @name)) @definition.type
(preproc_def name: (identifier) @name) @definition.macro
(preproc_function_def name: (identifier) @name) @definition.macro
(enumerator name: (identifier) @name) @definition.enumMember
(field_declaration declarator: (field_identifier) @name) @definition.field
(field_declaration declarator: (pointer_declarator declarator: (field_identifier) @name)) @definition.field
(translation_unit (declaration declarator: (init_declarator declarator: (identifier) @name)) @definition.variable)
(translation_unit (declaration declarator: (identifier) @name) @definition.variable)
"#;

const TYPESCRIPT: &str = r#"
(function_declaration name: (identifier) @name) @definition.function
(generator_function_declaration name: (identifier) @name) @definition.function
(function_signature name: (identifier) @name) @definition.function
(class_declaration name: (type_identifier) @name) @definition.class
(abstract_class_declaration name: (type_identifier) @name) @definition.class
(interface_declaration name: (type_identifier) @name) @definition.interface
(type_alias_declaration name: (type_identifier) @name) @definition.type
(enum_declaration name: (identifier) @name) @definition.enum
(internal_module name: (identifier) @name) @definition.module
(method_definition name: (property_identifier) @name) @definition.method
(method_signature name: (property_identifier) @name) @definition.method
(abstract_method_signature name: (property_identifier) @name) @definition.method
(public_field_definition name: (property_identifier) @name) @definition.field
(property_signature name: (property_identifier) @name) @definition.field
(variable_declarator name: (identifier) @name value: [(arrow_function) (function_expression)]) @definition.function
(program (lexical_declaration (variable_declarator name: (identifier) @name) @definition.constant))
(program (export_statement declaration: (lexical_declaration (variable_declarator name: (identifier) @name) @definition.constant)))
(program (variable_declaration (variable_declarator name: (identifier) @name) @definition.variable))
"#;

const JAVASCRIPT: &str = r#"
(function_declaration name: (identifier) @name) @definition.function
(generator_function_declaration name: (identifier) @name) @definition.function
(class_declaration name: (identifier) @name) @definition.class
(method_definition name: (property_identifier) @name) @definition.method
(field_definition property: (property_identifier) @name) @definition.field
(variable_declarator name: (identifier) @name value: [(arrow_function) (function_expression)]) @definition.function
(program (lexical_declaration (variable_declarator name: (identifier) @name) @definition.constant))
(program (export_statement declaration: (lexical_declaration (variable_declarator name: (identifier) @name) @definition.constant)))
(program (variable_declaration (variable_declarator name: (identifier) @name) @definition.variable))
"#;

const PYTHON: &str = r#"
(class_definition name: (identifier) @name) @definition.class
(class_definition body: (block (function_definition name: (identifier) @name) @definition.method))
(class_definition body: (block (decorated_definition definition: (function_definition name: (identifier) @name) @definition.method)))
(function_definition name: (identifier) @name) @definition.function
(module (expression_statement (assignment left: (identifier) @name) @definition.constant))
"#;

/// One definition in a file. Lines are 1-based; `column` is the 1-based
/// character (not byte) where the name starts.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Symbol {
    pub name: String,
    pub kind: String,
    pub line: u32,
    pub column: u32,
    pub end_line: u32,
    /// The definition it sits in (a type for a method or field), if any.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub container: Option<String>,
    /// How deeply it is nested in other definitions of the file.
    pub depth: u32,
    #[serde(skip)]
    pub start_byte: usize,
    #[serde(skip)]
    pub end_byte: usize,
}

pub fn parse(lang: Lang, text: &str) -> Option<Tree> {
    let mut parser = Parser::new();
    parser.set_language(&lang.language()).ok()?;
    parser.parse(text, None)
}

/// 1-based character column of a byte offset within its line.
fn char_column(text: &str, point: Point, byte: usize) -> u32 {
    let start = byte - point.column;
    text.get(start..byte)
        .map_or(point.column, |prefix| prefix.chars().count()) as u32
        + 1
}

/// The definitions of a file, in document order, nested by range.
pub fn symbols(lang: Lang, text: &str) -> Vec<Symbol> {
    let Some(tree) = parse(lang, text) else {
        return Vec::new();
    };
    symbols_in(lang, text, &tree)
}

pub fn symbols_in(lang: Lang, text: &str, tree: &Tree) -> Vec<Symbol> {
    let query = lang.query();
    let names = query.capture_names();
    let mut cursor = QueryCursor::new();
    // Name node start → (pattern, kind, definition node, name node).
    let mut found: HashMap<usize, (usize, String, Node, Node)> = HashMap::new();
    let mut matches = cursor.matches(query, tree.root_node(), text.as_bytes());
    while let Some(m) = matches.next() {
        let mut name = None;
        let mut definition = None;
        for capture in m.captures {
            let label = names[capture.index as usize];
            if label == "name" {
                name = Some(capture.node);
            } else if let Some(kind) = label.strip_prefix("definition.") {
                definition = Some((kind, capture.node));
            }
        }
        let (Some(name), Some((kind, node))) = (name, definition) else {
            continue;
        };
        let key = name.start_byte();
        if found.get(&key).is_none_or(|(at, ..)| m.pattern_index < *at) {
            found.insert(key, (m.pattern_index, kind.to_string(), node, name));
        }
    }
    let mut list: Vec<_> = found.into_values().collect();
    list.sort_by_key(|(_, _, node, name)| (node.start_byte(), name.start_byte()));
    let mut out = Vec::with_capacity(list.len());
    let mut stack: Vec<(usize, String)> = Vec::new();
    for (_, kind, node, name) in list {
        while stack
            .last()
            .is_some_and(|(end, _)| *end <= node.start_byte())
        {
            stack.pop();
        }
        let label = name.utf8_text(text.as_bytes()).unwrap_or("").to_string();
        let mut container = stack.last().map(|(_, name)| name.clone());
        if node.kind() == "method_declaration" {
            container = receiver_type(node, text).or(container);
        }
        let start = name.start_position();
        out.push(Symbol {
            name: label.clone(),
            kind,
            line: start.row as u32 + 1,
            column: char_column(text, start, name.start_byte()),
            end_line: node.end_position().row as u32 + 1,
            container,
            depth: stack.len() as u32,
            start_byte: node.start_byte(),
            end_byte: node.end_byte(),
        });
        stack.push((node.end_byte(), label));
    }
    out
}

/// A Go method's receiver type: `Sandbox` for `func (s *Sandbox) Start()`.
fn receiver_type(method: Node, text: &str) -> Option<String> {
    let receiver = method.child_by_field_name("receiver")?;
    let mut stack = vec![receiver];
    while let Some(node) = stack.pop() {
        if node.kind() == "type_identifier" {
            return node.utf8_text(text.as_bytes()).ok().map(str::to_string);
        }
        let mut cursor = node.walk();
        let children: Vec<_> = node.children(&mut cursor).collect();
        stack.extend(children.into_iter().rev());
    }
    None
}

fn is_identifier(node: &Node) -> bool {
    node.kind().ends_with("identifier") && node.child_count() == 0
}

/// Byte offset of a 1-based line and 1-based character column.
fn offset_of(text: &str, line: u32, column: u32) -> Option<usize> {
    let start = if line <= 1 {
        0
    } else {
        text.match_indices('\n').nth(line as usize - 2)?.0 + 1
    };
    let rest = &text[start..];
    let end = rest.find('\n').unwrap_or(rest.len());
    let line_text = &rest[..end];
    let at = line_text
        .char_indices()
        .nth(column.saturating_sub(1) as usize)
        .map_or(line_text.len(), |(i, _)| i);
    Some(start + at)
}

/// The identifier at a place (or just before it, as after a double-click).
pub fn identifier_at(lang: Lang, text: &str, line: u32, column: u32) -> Option<String> {
    let tree = parse(lang, text)?;
    let at = offset_of(text, line, column)?;
    let root = tree.root_node();
    for offset in [at, at.saturating_sub(1)] {
        if let Some(node) = root.descendant_for_byte_range(offset, offset) {
            if is_identifier(&node) {
                return node.utf8_text(text.as_bytes()).ok().map(str::to_string);
            }
        }
    }
    None
}

/// Where `name` occurs as an identifier in a file.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Occurrence {
    pub line: u32,
    pub column: u32,
    /// The line's text, trimmed, for a preview.
    pub preview: String,
}

pub fn preview(text: &str, line: u32) -> String {
    let full = text.lines().nth(line as usize - 1).unwrap_or("").trim();
    if full.chars().count() > 200 {
        full.chars().take(200).collect::<String>() + "…"
    } else {
        full.to_string()
    }
}

pub fn occurrences(lang: Lang, text: &str, name: &str) -> Vec<Occurrence> {
    if name.is_empty() || !text.contains(name) {
        return Vec::new();
    }
    let Some(tree) = parse(lang, text) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    let mut cursor = tree.walk();
    let mut descending = true;
    loop {
        let node = cursor.node();
        if descending && is_identifier(&node) && node.utf8_text(text.as_bytes()) == Ok(name) {
            let start = node.start_position();
            let line = start.row as u32 + 1;
            out.push(Occurrence {
                line,
                column: char_column(text, start, node.start_byte()),
                preview: preview(text, line),
            });
        }
        if descending && cursor.goto_first_child() {
            continue;
        }
        if cursor.goto_next_sibling() {
            descending = true;
            continue;
        }
        if !cursor.goto_parent() {
            break;
        }
        descending = false;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn names(lang: Lang, text: &str) -> Vec<(String, String, u32, Option<String>)> {
        symbols(lang, text)
            .into_iter()
            .map(|s| (s.name, s.kind, s.line, s.container))
            .collect()
    }

    fn has(list: &[(String, String, u32, Option<String>)], name: &str, kind: &str) -> bool {
        list.iter().any(|(n, k, ..)| n == name && k == kind)
    }

    #[test]
    fn every_language_loads_and_its_query_compiles() {
        for lang in ALL {
            assert!(parse(lang, "").is_some(), "{}", lang.id());
            let _ = lang.query();
        }
        assert_eq!(Lang::of("/a/b/main.GO"), Some(Lang::Go));
        assert_eq!(Lang::of("x.h"), Some(Lang::C));
        assert_eq!(Lang::of("x.tsx"), Some(Lang::Tsx));
        assert_eq!(Lang::of("README.md"), None);
        assert_eq!(Lang::of("Makefile"), None);
    }

    #[test]
    fn go_symbols() {
        let src = "package main\n\nconst Max = 3\n\nvar (\n\ta = 1\n)\n\ntype Sandbox struct {\n\tID string\n}\n\ntype Runner interface {\n\tRun() error\n}\n\nfunc (s *Sandbox) Start() error { return nil }\n\nfunc New() *Sandbox {\n\tx := 1\n\t_ = x\n\treturn &Sandbox{}\n}\n";
        let list = names(Lang::Go, src);
        assert!(has(&list, "Max", "constant"));
        assert!(has(&list, "a", "variable"));
        assert!(has(&list, "Sandbox", "struct"));
        assert!(has(&list, "ID", "field"));
        assert!(has(&list, "Runner", "interface"));
        assert!(has(&list, "Run", "method"));
        assert!(has(&list, "New", "function"));
        assert!(!list.iter().any(|(n, ..)| n == "x"));
        let start = list.iter().find(|(n, ..)| n == "Start").unwrap();
        assert_eq!(
            (start.1.as_str(), start.2, start.3.as_deref()),
            ("method", 17, Some("Sandbox"))
        );
        let id = symbols(Lang::Go, src)
            .into_iter()
            .find(|s| s.name == "ID")
            .unwrap();
        assert_eq!((id.depth, id.container.as_deref()), (1, Some("Sandbox")));
    }

    #[test]
    fn rust_symbols() {
        let src = "mod vm {\n    pub fn boot() {}\n}\nstruct Vm { id: u32 }\nenum State { Running }\ntrait Run { fn run(&self); }\nimpl Vm {\n    fn start(&self) {}\n}\nmacro_rules! m { () => {} }\nconst N: u8 = 1;\n";
        let list = names(Lang::Rust, src);
        assert!(has(&list, "vm", "module"));
        assert!(has(&list, "boot", "function"));
        assert!(has(&list, "Vm", "struct"));
        assert!(has(&list, "id", "field"));
        assert!(has(&list, "Running", "enumMember"));
        assert!(has(&list, "run", "method"));
        assert!(has(&list, "start", "method"));
        assert!(has(&list, "m", "macro"));
        assert!(has(&list, "N", "constant"));
        let start = list.iter().find(|(n, ..)| n == "start").unwrap();
        assert_eq!(start.3.as_deref(), Some("Vm"));
    }

    #[test]
    fn c_symbols() {
        let src = "#define MAX 4\nstruct vm { int fd; };\ntypedef struct vm vm_t;\nenum mode { FAST };\nint run(struct vm *v);\nstatic int *make(void) { return 0; }\nint run(struct vm *v) { return v->fd; }\nint counter = 0;\n";
        let list = names(Lang::C, src);
        assert!(has(&list, "MAX", "macro"));
        assert!(has(&list, "vm", "struct"));
        assert!(has(&list, "fd", "field"));
        assert!(has(&list, "vm_t", "type"));
        assert!(has(&list, "FAST", "enumMember"));
        assert!(has(&list, "run", "prototype"));
        assert!(has(&list, "run", "function"));
        assert!(has(&list, "make", "function"));
        assert!(has(&list, "counter", "variable"));
    }

    #[test]
    fn typescript_javascript_and_python_symbols() {
        let ts = "export interface Opts { a: string }\ntype Id = string;\nenum E { A }\nexport class Box { size = 1; open(): void {} }\nexport const make = () => new Box();\nconst LIMIT = 3;\nfunction run() { const inner = 1; }\n";
        for lang in [Lang::TypeScript, Lang::Tsx] {
            let list = names(lang, ts);
            assert!(has(&list, "Opts", "interface"));
            assert!(has(&list, "a", "field"));
            assert!(has(&list, "Id", "type"));
            assert!(has(&list, "E", "enum"));
            assert!(has(&list, "Box", "class"));
            assert!(has(&list, "size", "field"));
            assert!(has(&list, "open", "method"));
            assert!(has(&list, "make", "function"));
            assert!(has(&list, "LIMIT", "constant"));
            assert!(has(&list, "run", "function"));
            assert!(!list.iter().any(|(n, ..)| n == "inner"));
        }
        let js = "class A { x = 1; go() {} }\nexport const f = function () {};\nfunction g() {}\n";
        let list = names(Lang::JavaScript, js);
        assert!(has(&list, "A", "class"));
        assert!(has(&list, "x", "field"));
        assert!(has(&list, "go", "method"));
        assert!(has(&list, "f", "function"));
        assert!(has(&list, "g", "function"));
        let py = "LIMIT = 3\nclass Box:\n    @property\n    def size(self):\n        return 1\n    def open(self):\n        pass\ndef run():\n    x = 1\n";
        let list = names(Lang::Python, py);
        assert!(has(&list, "LIMIT", "constant"));
        assert!(has(&list, "Box", "class"));
        assert!(has(&list, "size", "method"));
        assert!(has(&list, "open", "method"));
        assert!(has(&list, "run", "function"));
        assert!(!list.iter().any(|(n, ..)| n == "x"));
    }

    #[test]
    fn identifiers_and_occurrences() {
        let src = "package p\n\n// Start é\nfunc Start() {}\n\nfunc main() {\n\tStart()\n\tvar é = Start\n\t_ = é\n}\n";
        assert_eq!(identifier_at(Lang::Go, src, 7, 2).as_deref(), Some("Start"));
        // Just after the word, as a caret lands after a double-click.
        assert_eq!(identifier_at(Lang::Go, src, 7, 7).as_deref(), Some("Start"));
        assert_eq!(identifier_at(Lang::Go, src, 2, 1), None);
        let found = occurrences(Lang::Go, src, "Start");
        assert_eq!(
            found.iter().map(|o| (o.line, o.column)).collect::<Vec<_>>(),
            vec![(4, 6), (7, 2), (8, 10)]
        );
        assert_eq!(found[1].preview, "Start()");
        // Columns count characters, not bytes.
        assert_eq!(occurrences(Lang::Go, src, "é")[1].column, 6);
        assert_eq!(identifier_at(Lang::Go, src, 9, 6).as_deref(), Some("é"));
    }
}
