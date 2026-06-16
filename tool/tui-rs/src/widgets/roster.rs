use std::process::Command;
use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Widget},
};

/// Health status of a roster member
#[derive(Debug, Clone)]
pub enum Health {
    Healthy,
    Untargeted,
    StaleTarget,
    MissingIdentity,
    Unknown,
}

impl Health {
    fn icon(&self) -> &str {
        match self {
            Health::Healthy => "✓",
            Health::Untargeted => "⚠",
            Health::StaleTarget => "✗",
            Health::MissingIdentity => "⚠",
            Health::Unknown => "?",
        }
    }

    fn color(&self) -> Color {
        match self {
            Health::Healthy => Color::Green,
            Health::Untargeted => Color::Yellow,
            Health::StaleTarget => Color::Red,
            Health::MissingIdentity => Color::Yellow,
            Health::Unknown => Color::Gray,
        }
    }
}

/// A roster member with health status
#[derive(Debug, Clone)]
pub struct RosterMember {
    pub name: String,
    pub adapter: String,
    pub wake: String,
    pub health: Health,
    pub issue: Option<String>,
}

/// Roster rail widget
pub struct RosterRail {
    pub members: Vec<RosterMember>,
    pub selected: usize,
}

impl RosterRail {
    /// Create a new roster rail by running `stitchpad doctor` and parsing the output
    pub fn from_doctor() -> Self {
        let members = Self::parse_doctor_output();
        Self { members, selected: 0 }
    }

    /// Parse the output of `stitchpad doctor`
    fn parse_doctor_output() -> Vec<RosterMember> {
        let output = Command::new("stitchpad")
            .arg("doctor")
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .unwrap_or_default();

        let mut members = Vec::new();

        for line in output.lines() {
            // Parse lines like:
            //   ✓ @dale (kitty/push) — healthy
            //   ⚠ @larry (kitty/push) — target '-' (no wake target, unreachable)
            //   ✗ @old-agent (kitty/push) — stale target — kitty window gone
            let trimmed = line.trim();
            if !trimmed.starts_with("✓") && !trimmed.starts_with("⚠") && !trimmed.starts_with("✗") && !trimmed.starts_with("?") {
                continue;
            }

            // Strip health icon + trailing space by char, not byte.
            // Icons (✓⚠✗?) are 3/3/3/1 UTF-8 bytes; byte-slice panics on 3-byte codepoints.
            let rest = trimmed
                .chars()
                .skip(1)           // skip health icon
                .collect::<String>()
                .trim()
                .to_string();

            // Extract @name
            let name = if let Some(at_pos) = rest.find('@') {
                let after_at = &rest[at_pos + 1..];
                after_at.split_whitespace().next()
                    .and_then(|s| s.split(|c: char| !c.is_alphanumeric() && c != '_' && c != '-').next())
                    .unwrap_or("")
                    .to_string()
            } else {
                continue;
            };

            // Extract adapter/wake from (adapter/wake)
            let adapter = rest.split('(').nth(1)
                .and_then(|s| s.split('/').next())
                .unwrap_or("")
                .to_string();
            let wake = rest.split('/').nth(1)
                .and_then(|s| s.split(')').next())
                .unwrap_or("")
                .to_string();

            // Determine health
            let (health, issue) = if rest.contains("healthy") {
                (Health::Healthy, None)
            } else if rest.contains("target '-'") || rest.contains("no wake target") {
                (Health::Untargeted, Some("no wake target".to_string()))
            } else if rest.contains("stale target") || rest.contains("gone") {
                (Health::StaleTarget, Some("window gone".to_string()))
            } else if rest.contains("no session identity") {
                (Health::MissingIdentity, Some("no session identity".to_string()))
            } else {
                (Health::Unknown, Some(rest.to_string()))
            };

            members.push(RosterMember { name, adapter, wake, health, issue });
        }

        members
    }

    /// Refresh the roster from the current doctor output
    pub fn refresh(&mut self) {
        self.members = Self::parse_doctor_output();
        if self.selected >= self.members.len() {
            self.selected = self.members.len().saturating_sub(1);
        }
    }

    /// Select the next member
    pub fn next(&mut self) {
        if !self.members.is_empty() {
            self.selected = (self.selected + 1) % self.members.len();
        }
    }

    /// Select the previous member
    pub fn previous(&mut self) {
        if !self.members.is_empty() {
            self.selected = (self.selected + self.members.len() - 1) % self.members.len();
        }
    }

    /// Get the currently selected member
    pub fn selected(&self) -> Option<&RosterMember> {
        self.members.get(self.selected)
    }
}

impl Widget for &RosterRail {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let block = Block::default()
            .title(" Roster ")
            .borders(Borders::ALL);

        let inner = block.inner(area);
        block.render(area, buf);

        if self.members.is_empty() {
            let empty = Line::from(Span::styled("  No members", Style::default().fg(Color::Gray)));
            buf.set_line(inner.x, inner.y, &empty, inner.width);
            return;
        }

        for (i, member) in self.members.iter().enumerate() {
            let y = inner.y + i as u16;
            if y >= inner.y + inner.height {
                break;
            }

            let style = if i == self.selected {
                Style::default().fg(member.health.color()).add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(member.health.color())
            };

            let icon_style = Style::default().fg(member.health.color());

            let line = Line::from(vec![
                Span::styled(format!(" {} ", member.health.icon()), icon_style),
                Span::styled(format!("@{}", member.name), style),
            ]);

            buf.set_line(inner.x, y, &line, inner.width);
        }
    }
}
