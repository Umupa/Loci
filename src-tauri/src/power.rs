//! Keeps the host awake while remote access is on.

use std::io;

#[cfg(target_os = "macos")]
use std::process::{Child, Command};

/// Holds a macOS power assertion until dropped.
///
/// `caffeinate -s` prevents system sleep while the Mac is on AC power.
/// `-w <pid>` ties its lifetime to this process, so a crash or a forced quit
/// does not leave an assertion behind.
pub struct KeepAwake {
    #[cfg(target_os = "macos")]
    child: Child,
}

impl KeepAwake {
    pub fn start() -> io::Result<Self> {
        #[cfg(target_os = "macos")]
        {
            let child = Command::new("/usr/bin/caffeinate")
                .arg("-s")
                .arg("-w")
                .arg(std::process::id().to_string())
                .spawn()?;
            Ok(Self { child })
        }

        #[cfg(not(target_os = "macos"))]
        {
            Ok(Self {})
        }
    }
}

#[cfg(target_os = "macos")]
impl Drop for KeepAwake {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[cfg(all(test, target_os = "macos"))]
mod tests {
    use super::*;
    use std::time::{Duration, Instant};

    fn pmset(args: &[&str]) -> String {
        let output = Command::new("/usr/bin/pmset")
            .args(args)
            .output()
            .expect("run pmset");
        String::from_utf8_lossy(&output.stdout).into_owned()
    }

    /// `caffeinate -s` only asserts while the Mac is on AC power.
    fn on_ac_power() -> bool {
        pmset(&["-g", "batt"]).contains("AC Power")
    }

    fn has_assertion(pid: u32) -> bool {
        pmset(&["-g", "assertions"]).lines().any(|line| {
            line.contains(&format!("pid {pid}(caffeinate)")) && line.contains("PreventSystemSleep")
        })
    }

    fn process_exists(pid: u32) -> bool {
        Command::new("/bin/kill")
            .arg("-0")
            .arg(pid.to_string())
            .status()
            .map(|status| status.success())
            .unwrap_or(false)
    }

    #[test]
    fn keep_awake_holds_and_releases_the_power_assertion() {
        let keep = KeepAwake::start().expect("start caffeinate");
        let pid = keep.child.id();

        if on_ac_power() {
            let deadline = Instant::now() + Duration::from_secs(10);
            while !has_assertion(pid) {
                assert!(
                    Instant::now() < deadline,
                    "caffeinate {pid} never held PreventSystemSleep"
                );
                std::thread::sleep(Duration::from_millis(100));
            }
        }

        drop(keep);
        assert!(!process_exists(pid), "caffeinate {pid} outlived KeepAwake");
    }
}
