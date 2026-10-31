//! Which Loci this is. The installed app (`com.loci.desktop`) holds the
//! user's real data and updates itself from GitHub Releases. Every debug
//! build, and any release build made with `tauri.dev.conf.json`, is
//! "Loci Dev": its own identifier, so its own data folder, window state and
//! notification grants, and it can run beside the installed app.

/// The installed app. Must match `identifier` in tauri.conf.json.
pub const RELEASE_IDENTIFIER: &str = "com.loci.desktop";
/// Must match `identifier` in tauri.dev.conf.json.
#[cfg(debug_assertions)]
pub const DEV_IDENTIFIER: &str = "com.loci.desktop.dev";
#[cfg(debug_assertions)]
pub const DEV_PRODUCT_NAME: &str = "Loci Dev";
/// Lets a second checkout (a worktree, a QA run) keep data of its own, for
/// example `LOCI_DEV_IDENTIFIER=com.loci.desktop.feeds npm run app:dev`.
#[cfg(debug_assertions)]
const DEV_IDENTIFIER_ENV: &str = "LOCI_DEV_IDENTIFIER";

/// The identifier a debug build runs under. Never the installed app's.
#[cfg(debug_assertions)]
pub fn dev_identifier() -> String {
    dev_identifier_from(std::env::var(DEV_IDENTIFIER_ENV).ok().as_deref())
}

#[cfg(debug_assertions)]
fn dev_identifier_from(value: Option<&str>) -> String {
    value
        .map(str::trim)
        .filter(|value| valid_dev_identifier(value))
        .map_or_else(|| DEV_IDENTIFIER.to_string(), str::to_string)
}

#[cfg(debug_assertions)]
fn valid_dev_identifier(value: &str) -> bool {
    value != RELEASE_IDENTIFIER
        && value.starts_with("com.loci.")
        && value.split('.').all(|part| {
            !part.is_empty() && part.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
        })
}

/// Debug builds run as Loci Dev whatever the configuration says, so a plain
/// `tauri dev` cannot open the installed app's database.
pub fn apply(context: &mut tauri::Context<tauri::Wry>) {
    #[cfg(debug_assertions)]
    {
        let config = context.config_mut();
        config.identifier = dev_identifier();
        config.product_name = Some(DEV_PRODUCT_NAME.into());
        // The orange DEV icon, in the windows and taskbars that take it from here.
        context.set_default_window_icon(Some(tauri::include_image!("icons/dev/128x128@2x.png")));
    }
    #[cfg(not(debug_assertions))]
    let _ = context;
}

/// Only the installed app updates itself; Loci Dev is built from source.
pub fn updates_itself(identifier: &str) -> bool {
    cfg!(not(debug_assertions)) && identifier == RELEASE_IDENTIFIER
}

#[cfg(all(test, debug_assertions))]
mod tests {
    use super::*;

    #[test]
    fn debug_builds_never_use_the_installed_identifier() {
        assert_eq!(dev_identifier_from(None), DEV_IDENTIFIER);
        assert_eq!(
            dev_identifier_from(Some(RELEASE_IDENTIFIER)),
            DEV_IDENTIFIER
        );
        assert_eq!(dev_identifier_from(Some("")), DEV_IDENTIFIER);
        assert_eq!(dev_identifier_from(Some("com.other.app")), DEV_IDENTIFIER);
        assert_eq!(
            dev_identifier_from(Some("com.loci.desktop/../x")),
            DEV_IDENTIFIER
        );
        assert_eq!(
            dev_identifier_from(Some(" com.loci.desktop.feeds ")),
            "com.loci.desktop.feeds"
        );
    }

    #[test]
    fn identifiers_match_the_configuration() {
        let release: serde_json::Value =
            serde_json::from_str(include_str!("../tauri.conf.json")).unwrap();
        let dev: serde_json::Value =
            serde_json::from_str(include_str!("../tauri.dev.conf.json")).unwrap();
        assert_eq!(release["identifier"], RELEASE_IDENTIFIER);
        assert_eq!(dev["identifier"], DEV_IDENTIFIER);
        assert_eq!(dev["productName"], DEV_PRODUCT_NAME);
    }

    #[test]
    fn only_the_installed_app_updates_itself() {
        // Debug builds are always Loci Dev.
        assert!(!updates_itself(RELEASE_IDENTIFIER));
        assert!(!updates_itself(DEV_IDENTIFIER));
    }
}
