#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("app") => std::process::exit(loci_lib::control_cli::run_app(
            std::env::args().skip(2).collect(),
        )),
        // The built-in Excalidraw tools, one call at a time.
        Some(namespace @ "canvas") => std::process::exit(loci_lib::control_cli::run_tool(
            namespace,
            std::env::args().skip(2).collect(),
        )),
        _ => {}
    }
    #[cfg(all(debug_assertions, target_os = "macos"))]
    loci_lib::ensure_macos_dev_bundle();
    loci_lib::run()
}
