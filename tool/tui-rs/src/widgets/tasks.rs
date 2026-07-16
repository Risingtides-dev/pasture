use ratatui::{
    buffer::Buffer,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Widget, Wrap},
};

/// A single ticket. Mirrors the locked per-ticket fenced block (randy, 03:57):
///   ```task TASK-1
///   title: ...
///   status: backlog|todo|in_progress|in_review|done|canceled
///   priority: none|low|medium|high|urgent
///   assignee: name
///   labels: a, b
///   created: 06-17 03:40
///   ---
///   description body (multi-line)
///   ```
/// ponytail: V1 fields only (id,title,status,priority,assignee,labels,created,description);
/// project/cycle/parent/estimate are phase-2 — parser ignores unknown keys, so adding
/// them later is zero-break.
#[derive(Debug, Clone, Default)]
pub struct Task {
    pub id: String,
    pub title: String,
    pub status: String,
    pub priority: String,
    pub assignee: String,
    pub labels: Vec<String>,
    pub created: String,
    pub description: String,
}

/// Kanban board: tickets bucketed into columns by status.
pub struct TaskBoard {
    pub tasks: Vec<Task>,
    pub selected: usize,
}

// Columns in Linear order. Anything with an unrecognised status lands in the last
// bucket so nothing is dropped silently.
const COLUMNS: [(&str, &str); 6] = [
    ("backlog", "BACKLOG"),
    ("todo", "TODO"),
    ("in_progress", "IN PROGRESS"),
    ("in_review", "IN REVIEW"),
    ("done", "DONE"),
    ("canceled", "CANCELED"),
];

fn priority_color(p: &str) -> Color {
    match p.trim().to_lowercase().as_str() {
        "urgent" => Color::Red,
        "high" => Color::LightRed,
        "medium" => Color::Yellow,
        "low" => Color::Blue,
        _ => Color::DarkGray, // none / unknown
    }
}

impl TaskBoard {
    pub fn from_pad() -> Self {
        Self {
            tasks: parse_tasks(),
            selected: 0,
        }
    }

    pub fn refresh(&mut self) {
        self.tasks = parse_tasks();
        if self.selected >= self.tasks.len() {
            self.selected = self.tasks.len().saturating_sub(1);
        }
    }

    pub fn next(&mut self) {
        if !self.tasks.is_empty() {
            self.selected = (self.selected + 1) % self.tasks.len();
        }
    }
    pub fn previous(&mut self) {
        if !self.tasks.is_empty() {
            self.selected = (self.selected + self.tasks.len() - 1) % self.tasks.len();
        }
    }

    pub fn selected_task(&self) -> Option<&Task> {
        self.tasks.get(self.selected)
    }

    /// Move the selected task one status column forward/back (backlog↔…↔done) via
    /// the CLI, then re-read. Canceling is explicit (`set_selected_status`), not on
    /// the arrow path, so ]] can't accidentally kill a ticket.
    pub fn move_selected(&mut self, forward: bool) {
        let Some(task) = self.selected_task() else { return };
        let cur = bucket(&task.status);
        let last_movable = 4; // done — ]/[ never walks into canceled
        let next = if forward {
            (cur + 1).min(last_movable)
        } else {
            cur.saturating_sub(1)
        };
        if next == cur || cur > last_movable {
            return;
        }
        self.set_selected_status(COLUMNS[next].0);
    }

    /// Set the selected task to an explicit status via the CLI, then re-read.
    pub fn set_selected_status(&mut self, status: &str) {
        let Some(task) = self.selected_task() else { return };
        let id = task.id.clone();
        let _ = std::process::Command::new("stitchpad")
            .args(["task", "move", &id, status])
            .output();
        self.refresh();
        // keep the same ticket selected across the re-read (it changed columns)
        if let Some(pos) = self.tasks.iter().position(|t| t.id == id) {
            self.selected = pos;
        }
    }
}

/// Centered overlay rect: `pct` of the area, clamped to sane minimums.
pub fn overlay_rect(area: Rect, pct_x: u16, pct_y: u16) -> Rect {
    let w = (area.width as u32 * pct_x as u32 / 100).max(30) as u16;
    let h = (area.height as u32 * pct_y as u32 / 100).max(8) as u16;
    let w = w.min(area.width);
    let h = h.min(area.height);
    Rect {
        x: area.x + (area.width - w) / 2,
        y: area.y + (area.height - h) / 2,
        width: w,
        height: h,
    }
}

/// Full-field detail card for one task, rendered as a modal overlay.
pub fn render_detail(task: &Task, area: Rect, buf: &mut Buffer) {
    let rect = overlay_rect(area, 70, 60);
    ratatui::widgets::Clear.render(rect, buf);
    let block = Block::default()
        .title(format!(" {} ", task.id))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Cyan));
    let inner = block.inner(rect);
    block.render(rect, buf);

    let label = Style::default().fg(Color::Rgb(128, 128, 128));
    let mut lines: Vec<Line> = vec![
        Line::from(Span::styled(
            task.title.clone(),
            Style::default().add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from(vec![
            Span::styled("status   ", label),
            Span::styled(task.status.clone(), Style::default().fg(Color::Cyan)),
            Span::styled("   priority ", label),
            Span::styled(
                task.priority.clone(),
                Style::default().fg(priority_color(&task.priority)),
            ),
        ]),
        Line::from(vec![
            Span::styled("assignee ", label),
            Span::styled(
                format!("@{}", task.assignee),
                Style::default().fg(crate::color::color_for(&task.assignee)),
            ),
            Span::styled("   created ", label),
            Span::raw(task.created.clone()),
        ]),
    ];
    if !task.labels.is_empty() {
        lines.push(Line::from(vec![
            Span::styled("labels   ", label),
            Span::raw(task.labels.join(", ")),
        ]));
    }
    lines.push(Line::from(""));
    for l in task.description.lines() {
        lines.push(Line::from(l.to_string()));
    }
    lines.push(Line::from(""));
    lines.push(Line::from(Span::styled(
        "Esc:close   ]/[:move status   d:done   x:cancel",
        label,
    )));
    Paragraph::new(lines)
        .wrap(Wrap { trim: false })
        .render(inner, buf);
}

/// Collect every ```task <ID> block from the pad and parse its key:value frontmatter
/// + description body. Key:value (not pipe) means titles/descriptions hold any char.
/// Unreadable pad or no blocks → empty (view shows its empty state).
fn parse_tasks() -> Vec<Task> {
    match std::fs::read_to_string(".stitchpad/stitchpad.md") {
        Ok(s) => parse_tasks_str(&s),
        Err(_) => Vec::new(),
    }
}

fn parse_tasks_str(pad: &str) -> Vec<Task> {
    let mut tasks = Vec::new();
    let mut cur: Option<Task> = None;
    let mut in_body = false; // past the --- separator → collecting description

    for line in pad.lines() {
        let t = line.trim_end();
        let tt = t.trim();

        if let Some(rest) = tt.strip_prefix("```task") {
            // start of a ticket block; ID is the token after ```task
            let mut task = Task::default();
            task.id = rest.trim().to_string();
            cur = Some(task);
            in_body = false;
            continue;
        }

        if cur.is_some() && tt == "```" {
            // end of the current ticket block
            if let Some(task) = cur.take() {
                if !task.id.is_empty() || !task.title.is_empty() {
                    tasks.push(task);
                }
            }
            in_body = false;
            continue;
        }

        let Some(task) = cur.as_mut() else { continue };

        if !in_body && tt == "---" {
            in_body = true;
            continue;
        }

        if in_body {
            // description body, multi-line — preserve line breaks, trim leading blank
            if task.description.is_empty() && tt.is_empty() {
                continue;
            }
            if !task.description.is_empty() {
                task.description.push('\n');
            }
            task.description.push_str(t);
            continue;
        }

        // frontmatter: skip # comment lines (contract pt.4 w/ lib.sh sp_tasks), then key: value
        if tt.starts_with('#') {
            continue;
        }
        if let Some((k, v)) = tt.split_once(':') {
            let (k, v) = (k.trim().to_lowercase(), v.trim());
            match k.as_str() {
                "title" => task.title = v.to_string(),
                "status" => task.status = v.to_lowercase(),
                "priority" => task.priority = v.to_lowercase(),
                "assignee" => task.assignee = v.trim_start_matches('@').to_string(),
                "labels" => {
                    task.labels = v
                        .split(',')
                        .map(|s| s.trim().to_string())
                        .filter(|s| !s.is_empty())
                        .collect()
                }
                "created" => task.created = v.to_string(),
                _ => {} // phase-2 fields (project/cycle/parent/estimate) ignored, no break
            }
        }
    }
    tasks
}

impl Widget for &TaskBoard {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let outer = Block::default().title(" Tasks ").borders(Borders::ALL);
        let inner = outer.inner(area);
        outer.render(area, buf);

        if self.tasks.is_empty() {
            let msg = Paragraph::new(
                "No tasks yet.\n\nTickets live as fenced ```task TASK-N blocks in \
                 stitchpad.md (key:value frontmatter). Add one with `stitchpad task new` \
                 and it shows here as a kanban card.",
            )
            .style(Style::default().fg(Color::DarkGray))
            .wrap(Wrap { trim: true });
            msg.render(inner, buf);
            return;
        }

        // Only render columns that have tickets, so 6 columns don't crush card width
        // on a narrow terminal. (Empty Linear columns are noise here.)
        let cols_with_tasks: Vec<(usize, &str, &str)> = COLUMNS
            .iter()
            .enumerate()
            .filter_map(|(ci, (key, label))| {
                let has = self.tasks.iter().any(|t| bucket(&t.status) == ci);
                if has { Some((ci, *key, *label)) } else { None }
            })
            .collect();
        if cols_with_tasks.is_empty() {
            return;
        }

        let n = cols_with_tasks.len() as u32;
        let constraints: Vec<Constraint> =
            (0..n).map(|_| Constraint::Ratio(1, n)).collect();
        let layout = Layout::default()
            .direction(Direction::Horizontal)
            .constraints(constraints)
            .split(inner);

        for (slot, (ci, _key, label)) in cols_with_tasks.iter().enumerate() {
            let col_tasks: Vec<(usize, &Task)> = self
                .tasks
                .iter()
                .enumerate()
                .filter(|(_, t)| bucket(&t.status) == *ci)
                .collect();

            let col_block = Block::default()
                .title(format!(" {} ({}) ", label, col_tasks.len()))
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray));
            let col_inner = col_block.inner(layout[slot]);
            col_block.render(layout[slot], buf);

            let mut y = col_inner.y;
            for (ti, task) in &col_tasks {
                if y + 1 >= col_inner.y + col_inner.height {
                    break;
                }
                let selected = *ti == self.selected;
                let acc = crate::color::color_for(&task.assignee);
                let title_style = if selected {
                    Style::default().fg(Color::White).add_modifier(Modifier::BOLD)
                } else {
                    Style::default().fg(Color::Gray)
                };
                // line 1: priority dot + ID + title
                let card = Line::from(vec![
                    Span::styled("● ", Style::default().fg(priority_color(&task.priority))),
                    Span::styled(
                        format!("{} ", task.id),
                        Style::default().fg(Color::DarkGray),
                    ),
                    Span::styled(task.title.clone(), title_style),
                ]);
                buf.set_line(col_inner.x, y, &card, col_inner.width);
                // line 2: @assignee (agent-colored) + label chips
                let mut meta = vec![Span::styled(
                    format!("  @{}", task.assignee),
                    Style::default().fg(acc),
                )];
                for l in &task.labels {
                    meta.push(Span::styled(
                        format!(" [{}]", l),
                        Style::default().fg(Color::DarkGray),
                    ));
                }
                buf.set_line(col_inner.x, y + 1, &Line::from(meta), col_inner.width);
                y += 3; // card + meta + gap
            }
        }
    }
}

/// Which column index a status falls into. Unknown status → last column (canceled
/// bucket) so it's visible, never dropped.
fn bucket(status: &str) -> usize {
    let s = status.trim().to_lowercase();
    COLUMNS
        .iter()
        .position(|(k, _)| *k == s)
        .unwrap_or(COLUMNS.len() - 1)
}

#[cfg(test)]
mod tests {
    use super::*;
    const PAD: &str = "\
# pad
```roster
dale | claude | push | -
```
```task TASK-1
title: wire MCP | with a pipe in title
status: in_progress
priority: high
assignee: ernie
labels: infra, installer
created: 06-17 03:40
---
description body here
multi-line ok
```
```task TASK-2
title: tasks TUI tab
status: todo
priority: medium
assignee: dale
labels: ui
---
the body
```
";

    #[test]
    fn parses_two_tickets_with_edge_cases() {
        let t = parse_tasks_str(PAD);
        assert_eq!(t.len(), 2, "should find both task blocks, not the roster block");
        // pipe in title survives (key:value, not pipe-delimited)
        assert_eq!(t[0].id, "TASK-1");
        assert_eq!(t[0].title, "wire MCP | with a pipe in title");
        assert_eq!(t[0].status, "in_progress");
        assert_eq!(t[0].assignee, "ernie");
        assert_eq!(t[0].labels, vec!["infra", "installer"]);
        // multi-line description body preserved
        assert_eq!(t[0].description, "description body here\nmulti-line ok");
        // unknown status would bucket to last column; known ones map correctly
        assert_eq!(bucket("in_progress"), 2);
        assert_eq!(bucket("done"), 4);
        assert_eq!(bucket("bogus"), COLUMNS.len() - 1);
    }

    #[test]
    fn empty_pad_no_tasks() {
        assert!(parse_tasks_str("# just a pad\nno blocks").is_empty());
    }
}

