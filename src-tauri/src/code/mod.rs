//! Code reading: files at a pinned commit, and (later) symbols, definitions
//! and references. Read-only, local and lightweight: git and tree-sitter.

pub mod commands;
pub mod git;
pub mod lang;
pub mod nav;
