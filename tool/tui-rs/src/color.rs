use ratatui::style::Color;

/// Curated 20-color palette of visually distinct hues (256-color indices).
/// Wide enough to avoid collisions for typical rosters (up to 20 agents).
const PALETTE: [u8; 20] = [
    39,   // blue
    208,  // orange
    76,   // green
    170,  // pink
    214,  // yellow-orange
    51,   // cyan
    199,  // magenta
    220,  // gold
    123,  // light cyan
    141,  // lavender
    203,  // salmon
    82,   // lime
    205,  // hot pink
    114,  // light green
    177,  // orchid
    226,  // bright yellow
    87,   // sky blue
    213,  // pink-purple
    155,  // pale green
    159,  // ice blue
];

/// Hash a name to a palette index (deterministic, position-independent).
fn hash_name(name: &str) -> usize {
    let sum: u32 = name.chars().map(|c| c as u32).sum();
    (sum as usize) % PALETTE.len()
}

/// Assign collision-aware colors to a list of names.
/// Walks names in order; each name gets its hashed slot, but if already taken,
/// advances to the next free slot. Returns a Vec of (name, Color) in input order.
pub fn assign_colors(names: &[&str]) -> Vec<(&str, Color)> {
    let mut taken = vec![false; PALETTE.len()];
    let mut result = Vec::with_capacity(names.len());

    for &name in names {
        let hash_idx = hash_name(name);
        let mut idx = hash_idx;

        // Linear probe for next free slot
        while taken[idx] {
            idx = (idx + 1) % PALETTE.len();
            // Safety: if all slots taken, wrap around to hash (shouldn't happen with 20 slots)
            if idx == hash_idx {
                break;
            }
        }

        taken[idx] = true;
        result.push((name, Color::Indexed(PALETTE[idx])));
    }

    result
}

/// Get a single name's color given the full roster (collision-aware).
/// Use this when you know the full roster and want distinct colors.
pub fn color_for_with_roster(name: &str, roster: &[&str]) -> Color {
    let assignments = assign_colors(roster);
    assignments
        .iter()
        .find(|(n, _)| *n == name)
        .map(|(_, c)| *c)
        .unwrap_or(Color::Gray)
}

/// Simple hash-based color (no collision awareness).
/// Use only when the full roster is unknown; prefer `color_for_with_roster`.
pub fn color_for_simple(name: &str) -> Color {
    let idx = hash_name(name);
    Color::Indexed(PALETTE[idx])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seven_members_distinct() {
        let roster = vec!["dale", "larry", "ernie", "dennis", "Jill", "mark", "john"];
        let assignments = assign_colors(&roster);
        let colors: Vec<Color> = assignments.iter().map(|(_, c)| *c).collect();

        // All 7 must be distinct
        let mut sorted = colors.clone();
        sorted.sort_by_key(|c| match c { Color::Indexed(i) => *i, _ => 0 });
        sorted.dedup();
        assert_eq!(sorted.len(), colors.len(), "collision detected: {:?}", assignments);
    }

    #[test]
    fn john_and_jill_distinct() {
        let roster = vec!["john", "Jill"];
        let assignments = assign_colors(&roster);
        assert_ne!(assignments[0].1, assignments[1].1, "john and Jill should have different colors");
    }

    #[test]
    fn deterministic() {
        let roster = vec!["dale", "larry", "ernie"];
        let a1 = assign_colors(&roster);
        let a2 = assign_colors(&roster);
        assert_eq!(a1, a2);
    }
}
