//! Code reading: files at a pinned commit, and (later) symbols, definitions
//! and references. Read-only, local and lightweight: git and tree-sitter.

pub mod commands;
pub mod git;
#[allow(dead_code)] // identifiers and occurrences serve definitions and references, next.
pub mod lang;
