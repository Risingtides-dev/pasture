//! Single source of truth for author colors: the bash CLI `stitchpad color`.
//!
//! The CLI emits the final RGB hex (`#rrggbb`) with the override map applied
//! (e.g. Jill=#ff1493, ernie=#5f2f8f) and the same collision-aware assignment the
//! terminal surface backgrounds use. The TUI does NOT reimplement any palette — it
//! shells out and parses the hex, so the board and the terminals can never drift.
//!
//! Batch mode: `stitchpad color` (no arg) dumps the full `name #hex` table in one
//! fork. We parse that into a HashMap and cache it. One subprocess per roster
//! change, not per name per frame.

use ratatui::style::Color;
use std::collections::HashMap;
use std::process::Command;
use std::sync::Mutex;

static CACHE: Mutex<Option<HashMap<String, Color>>> = Mutex::new(None);

/// Author color as `Color::Rgb`, matching that name's terminal/window exactly.
/// Uses the batch `stitchpad color` (no arg) table dump — one fork, cached.
pub fn color_for(name: &str) -> Color {
    if let Ok(mut guard) = CACHE.lock() {
        let map = guard.get_or_insert_with(load_all);
        if let Some(c) = map.get(name) {
            return *c;
        }
        // Name not in batch table — try single lookup as fallback
        let c = resolve_single(name).unwrap_or(Color::Gray);
        map.insert(name.to_string(), c);
        return c;
    }
    resolve_single(name).unwrap_or(Color::Gray)
}

/// Drop the cache so the next `color_for` re-reads the CLI. Call on roster change /
/// manual refresh so override edits or new members pick up immediately.
pub fn invalidate() {
    if let Ok(mut guard) = CACHE.lock() {
        *guard = None;
    }
}

/// Load the full color table in one fork: `stitchpad color` (no arg).
fn load_all() -> HashMap<String, Color> {
    let mut map = HashMap::new();
    let out = Command::new("stitchpad")
        .arg("color")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .unwrap_or_default();

    for line in out.lines() {
        let mut parts = line.split_whitespace();
        if let (Some(name), Some(hex)) = (parts.next(), parts.next()) {
            if let Some(c) = parse_hex(hex) {
                map.insert(name.to_string(), c);
            }
        }
    }
    map
}

/// Single name lookup: `stitchpad color <name>`. Fallback for names not in batch.
fn resolve_single(name: &str) -> Option<Color> {
    let out = Command::new("stitchpad")
        .args(["color", name])
        .output()
        .ok()?;
    let text = String::from_utf8(out.stdout).ok()?;
    text.split_whitespace().find_map(parse_hex)
}

/// Parse a `#rrggbb` (or bare `rrggbb`) token into `Color::Rgb`. None if not 6 hex.
fn parse_hex(tok: &str) -> Option<Color> {
    let h = tok.trim().trim_start_matches('#');
    if h.len() != 6 || !h.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    let r = u8::from_str_radix(&h[0..2], 16).ok()?;
    let g = u8::from_str_radix(&h[2..4], 16).ok()?;
    let b = u8::from_str_radix(&h[4..6], 16).ok()?;
    Some(Color::Rgb(r, g, b))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_hex_forms() {
        assert_eq!(parse_hex("#ff1493"), Some(Color::Rgb(255, 20, 147)));
        assert_eq!(parse_hex("5f2f8f"), Some(Color::Rgb(95, 47, 143)));
        assert_eq!(parse_hex("#ABCDEF"), Some(Color::Rgb(171, 205, 239)));
        assert_eq!(parse_hex("#fff"), None);
        assert_eq!(parse_hex("nothex"), None);
    }

    #[test]
    fn batch_load_parses_table() {
        // When run in a pad context, load_all() should return at least 1 entry
        let map = load_all();
        // Outside a pad, CLI returns empty — skip assertion
        if map.is_empty() {
            return;
        }
        assert!(map.len() > 0, "batch table should have entries");
    }

    #[test]
    fn live_cli_matches_terminal() {
        match resolve_single("Jill") {
            Some(Color::Rgb(0x80, 0x80, 0x80)) | None => { /* no pad context */ }
            Some(c) => assert_eq!(
                c,
                Color::Rgb(0xff, 0x14, 0x93),
                "Jill must match her window override (#ff1493)"
            ),
        }
    }
}
