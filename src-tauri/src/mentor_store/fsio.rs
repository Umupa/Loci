//! Writing files so that a crash never leaves half of one, and the small
//! helpers every file format shares: hashes, sizes and ISO-8601 times.

use std::io::Write;
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::UNIX_EPOCH;

use sha2::{Digest, Sha256};

static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Writes `bytes` to `path` through a temporary file in the same folder and a
/// rename, so readers (and the watcher) see the old file or the new one.
pub fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let dir = path
        .parent()
        .ok_or_else(|| format!("No folder for {}", path.display()))?;
    std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| format!("Not a file name: {}", path.display()))?;
    let temp = dir.join(format!(
        ".{name}.loci-{}-{}.tmp",
        std::process::id(),
        TEMP_COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    let result = (|| {
        let mut file =
            std::fs::File::create(&temp).map_err(|e| format!("{}: {e}", temp.display()))?;
        file.write_all(bytes)
            .map_err(|e| format!("{}: {e}", temp.display()))?;
        file.sync_all()
            .map_err(|e| format!("{}: {e}", temp.display()))?;
        std::fs::rename(&temp, path).map_err(|e| format!("{}: {e}", path.display()))
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&temp);
    }
    result
}

pub fn sha256(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

/// Size and modification time in nanoseconds, the cheap test for "changed".
pub fn stamp(meta: &std::fs::Metadata) -> (i64, i64) {
    let mtime = meta
        .modified()
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_nanos() as i64);
    (meta.len() as i64, mtime)
}

/// Milliseconds since the epoch as `2026-11-01T09:12:00.000Z`.
pub fn iso_from_millis(millis: i64) -> String {
    let secs = millis.div_euclid(1000);
    let ms = millis.rem_euclid(1000);
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    format!(
        "{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}.{ms:03}Z",
        rem / 3600,
        (rem % 3600) / 60,
        rem % 60
    )
}

/// Reads `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM[:SS[.fff]]` with `Z` or `±HH:MM`,
/// or a plain number of milliseconds.
pub fn millis_from_iso(text: &str) -> Option<i64> {
    let text = text.trim();
    if let Ok(number) = text.parse::<i64>() {
        return Some(number);
    }
    let bytes = text.as_bytes();
    if bytes.len() < 10 || bytes[4] != b'-' || bytes[7] != b'-' {
        return None;
    }
    let year: i64 = text.get(0..4)?.parse().ok()?;
    let month: u32 = text.get(5..7)?.parse().ok()?;
    let day: u32 = text.get(8..10)?.parse().ok()?;
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    let mut seconds = days_from_civil(year, month, day) * 86_400;
    let mut millis = 0i64;
    let rest = &text[10..];
    if let Some(time) = rest.strip_prefix('T').or_else(|| rest.strip_prefix(' ')) {
        let (clock, offset) = split_offset(time)?;
        let mut parts = clock.split(':');
        let hour: i64 = parts.next()?.parse().ok()?;
        let minute: i64 = parts.next()?.parse().ok()?;
        let second_text = parts.next().unwrap_or("0");
        let (whole, fraction) = second_text.split_once('.').unwrap_or((second_text, ""));
        let second: i64 = whole.parse().ok()?;
        if hour > 23 || minute > 59 || second > 60 {
            return None;
        }
        let fraction: String = fraction.chars().chain("000".chars()).take(3).collect();
        millis = fraction.parse().ok()?;
        seconds += hour * 3600 + minute * 60 + second - offset;
    } else if !rest.is_empty() {
        return None;
    }
    Some(seconds * 1000 + millis)
}

fn split_offset(time: &str) -> Option<(&str, i64)> {
    if let Some(clock) = time.strip_suffix('Z') {
        return Some((clock, 0));
    }
    if let Some(at) = time.rfind(['+', '-']) {
        let (clock, offset) = time.split_at(at);
        let sign = if offset.starts_with('-') { -1 } else { 1 };
        let digits = offset[1..].replace(':', "");
        if digits.len() == 4 {
            let hours: i64 = digits[..2].parse().ok()?;
            let minutes: i64 = digits[2..].parse().ok()?;
            return Some((clock, sign * (hours * 3600 + minutes * 60)));
        }
    }
    Some((time, 0))
}

// Howard Hinnant's civil calendar conversions.
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

fn days_from_civil(year: i64, month: u32, day: u32) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y.rem_euclid(400);
    let m = month as i64;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + day as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn times_round_trip_through_iso() {
        for millis in [0, 1_793_000_000_123, 951_782_400_000, -86_400_000] {
            assert_eq!(millis_from_iso(&iso_from_millis(millis)), Some(millis));
        }
        assert_eq!(iso_from_millis(0), "1970-01-01T00:00:00.000Z");
        assert_eq!(millis_from_iso("2026-11-01"), Some(1_793_491_200_000));
        assert_eq!(
            millis_from_iso("2026-11-01T08:00:00+08:00"),
            Some(1_793_491_200_000)
        );
        assert_eq!(millis_from_iso("1700000000000"), Some(1_700_000_000_000));
        assert_eq!(millis_from_iso("yesterday"), None);
    }

    #[test]
    fn an_atomic_write_replaces_the_file_and_leaves_no_temp_file() {
        let dir = std::env::temp_dir().join(format!("loci-fsio-{}", uuid::Uuid::new_v4()));
        let path = dir.join("a/b.md");
        write_atomic(&path, b"one").unwrap();
        write_atomic(&path, b"two").unwrap();
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "two");
        assert_eq!(std::fs::read_dir(dir.join("a")).unwrap().count(), 1);
        std::fs::remove_dir_all(dir).unwrap();
    }
}
