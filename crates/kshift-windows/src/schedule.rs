//! People-schedule layout rules.
//!
//! These rules mirror the `KS-UI` people-schedule rules: people rows, date
//! columns, lane packing without overlap, priority tint and status colors.

use chrono::{Datelike, Duration, NaiveDate};

use crate::model::{Priority, Snapshot, Status, Task};

/// P0 tint, matching `UI-PPL-006`.
pub const PRIORITY_URGENT: u32 = 0xD9_2D_3A;
/// P1 tint, matching `UI-PPL-006`.
pub const PRIORITY_HIGH: u32 = 0xFF_C4_00;
/// P2 tint, matching `UI-PPL-006`.
pub const PRIORITY_MEDIUM: u32 = 0x00_66_FF;
/// P3 tint, matching `UI-PPL-006`.
pub const PRIORITY_LOW: u32 = 0x5F_63_68;

/// `todo` status color, matching `UI-PPL-017`.
pub const STATUS_TODO: u32 = 0x8E_8E_93;
/// `in_progress` status color, matching `UI-PPL-017`.
pub const STATUS_IN_PROGRESS: u32 = 0x0A_84_FF;
/// `blocked` status color, matching `UI-PPL-017`.
pub const STATUS_BLOCKED: u32 = 0xFF_45_3A;
/// `done` status color, matching `UI-PPL-017`.
pub const STATUS_DONE: u32 = 0x30_D1_58;

/// Row identifier for tasks without an assignee.
pub const UNASSIGNED_ID: &str = "unassigned";
/// Row label for tasks without an assignee.
pub const UNASSIGNED_NAME: &str = "未分配";

/// One task bar inside a person row.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Bar {
    /// Index into `Snapshot::tasks`.
    pub task_index: usize,
    /// First visible day index. Zero is the window start.
    pub start_index: i64,
    /// Last visible day index.
    pub end_index: i64,
    /// Lane inside the row. Lane zero is the top lane.
    pub lane: usize,
    /// The bar is clipped at the left window edge.
    pub clipped_start: bool,
    /// The bar is clipped at the right window edge.
    pub clipped_end: bool,
}

impl Bar {
    /// Number of visible days.
    pub fn day_count(&self) -> i64 {
        self.end_index - self.start_index + 1
    }
}

/// One person row.
#[derive(Debug, Clone)]
pub struct PersonRow {
    /// Member identifier, or `UNASSIGNED_ID`.
    pub id: String,
    /// Display name.
    pub name: String,
    /// Role label. Empty for the unassigned row.
    pub role_label: String,
    /// Visible task count.
    pub task_count: usize,
    /// Visible tasks in progress.
    pub in_progress_count: usize,
    /// Visible P0 tasks.
    pub urgent_count: usize,
    /// Bars in priority order.
    pub bars: Vec<Bar>,
}

/// Parse one `YYYY-MM-DD` date.
pub fn parse_date(value: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(value.trim(), "%Y-%m-%d").ok()
}

/// Monday of the calendar week that contains `date`.
pub fn week_start(date: NaiveDate) -> NaiveDate {
    let offset = i64::from(date.weekday().num_days_from_monday());
    date - Duration::days(offset)
}

/// Seven natural dates starting at `start`.
pub fn week_days(start: NaiveDate) -> Vec<NaiveDate> {
    (0..7)
        .map(|offset| start + Duration::days(offset))
        .collect()
}

/// Effective schedule span.
///
/// `starts_on` wins over `planned_on`. `due_on` wins over `planned_on`. An
/// inverted range is swapped.
pub fn schedule_span(task: &Task) -> Option<(NaiveDate, NaiveDate)> {
    let planned = parse_date(&task.planned_on)?;
    let start = task
        .starts_on
        .as_deref()
        .and_then(parse_date)
        .unwrap_or(planned);
    let end = task
        .due_on
        .as_deref()
        .and_then(parse_date)
        .unwrap_or(planned);
    Some(if end < start {
        (end, start)
    } else {
        (start, end)
    })
}

/// Priority tint.
pub fn priority_color(priority: Priority) -> u32 {
    match priority {
        Priority::Urgent => PRIORITY_URGENT,
        Priority::High => PRIORITY_HIGH,
        Priority::Medium => PRIORITY_MEDIUM,
        Priority::Low => PRIORITY_LOW,
    }
}

/// Status color.
pub fn status_color(status: Status) -> u32 {
    match status {
        Status::Todo => STATUS_TODO,
        Status::InProgress => STATUS_IN_PROGRESS,
        Status::Blocked => STATUS_BLOCKED,
        Status::Done => STATUS_DONE,
    }
}

/// Status glyph name, matching the macOS status badge symbols.
pub fn status_glyph(status: Status) -> &'static str {
    match status {
        Status::Todo => "○",
        Status::InProgress => "◔",
        Status::Blocked => "▲",
        Status::Done => "✓",
    }
}

/// Weekday label.
pub fn weekday_label(date: NaiveDate) -> &'static str {
    match date.weekday().num_days_from_monday() {
        0 => "周一",
        1 => "周二",
        2 => "周三",
        3 => "周四",
        4 => "周五",
        5 => "周六",
        _ => "周日",
    }
}

/// Short `MM/DD` date label.
pub fn date_label(date: NaiveDate) -> String {
    format!("{:02}/{:02}", date.month(), date.day())
}

/// Build all person rows for one window.
///
/// Rows follow member order. A final row collects tasks with no assignee when
/// any such task is visible.
pub fn build_rows(snapshot: &Snapshot, window_start: NaiveDate, day_count: i64) -> Vec<PersonRow> {
    let mut rows = Vec::with_capacity(snapshot.members.len() + 1);
    for member in &snapshot.members {
        let indices = ordered_task_indices(snapshot, window_start, day_count, |task| {
            task.assignee_ids.iter().any(|id| id == &member.user_id)
        });
        rows.push(build_row(RowInput {
            id: member.user_id.clone(),
            name: member.display_name.clone(),
            role_label: member.role.label().to_owned(),
            snapshot,
            indices,
            window_start,
            day_count,
        }));
    }
    let unassigned = ordered_task_indices(snapshot, window_start, day_count, |task| {
        task.assignee_ids.is_empty()
    });
    if !unassigned.is_empty() {
        rows.push(build_row(RowInput {
            id: UNASSIGNED_ID.to_owned(),
            name: UNASSIGNED_NAME.to_owned(),
            role_label: String::new(),
            snapshot,
            indices: unassigned,
            window_start,
            day_count,
        }));
    }
    rows
}

struct RowInput<'a> {
    id: String,
    name: String,
    role_label: String,
    snapshot: &'a Snapshot,
    indices: Vec<usize>,
    window_start: NaiveDate,
    day_count: i64,
}

struct Span {
    task_index: usize,
    start_index: i64,
    end_index: i64,
    clipped_start: bool,
    clipped_end: bool,
}

fn ordered_task_indices(
    snapshot: &Snapshot,
    window_start: NaiveDate,
    day_count: i64,
    filter: impl Fn(&Task) -> bool,
) -> Vec<usize> {
    let mut indices: Vec<usize> = snapshot
        .tasks
        .iter()
        .enumerate()
        .filter(|(_, task)| filter(task) && visible(task, window_start, day_count))
        .map(|(index, _)| index)
        .collect();
    indices.sort_by(|left, right| {
        let left = &snapshot.tasks[*left];
        let right = &snapshot.tasks[*right];
        right
            .priority
            .cmp(&left.priority)
            .then_with(|| status_rank(left.status).cmp(&status_rank(right.status)))
            .then_with(|| left.title.cmp(&right.title))
            .then_with(|| left.id.cmp(&right.id))
    });
    indices
}

fn status_rank(status: Status) -> u8 {
    match status {
        Status::InProgress => 0,
        Status::Todo => 1,
        Status::Blocked => 2,
        Status::Done => 3,
    }
}

fn visible(task: &Task, window_start: NaiveDate, day_count: i64) -> bool {
    match schedule_span(task) {
        Some((start, end)) => {
            let start_index = (start - window_start).num_days();
            let end_index = (end - window_start).num_days();
            end_index >= 0 && start_index < day_count
        }
        None => false,
    }
}

fn build_row(input: RowInput<'_>) -> PersonRow {
    let RowInput {
        id,
        name,
        role_label,
        snapshot,
        indices,
        window_start,
        day_count,
    } = input;
    let mut spans = Vec::with_capacity(indices.len());
    for index in &indices {
        let task = &snapshot.tasks[*index];
        if let Some((start, end)) = schedule_span(task) {
            let raw_start = (start - window_start).num_days();
            let raw_end = (end - window_start).num_days();
            let start_index = raw_start.max(0);
            let end_index = raw_end.min(day_count - 1);
            if start_index <= end_index {
                spans.push(Span {
                    task_index: *index,
                    start_index,
                    end_index,
                    clipped_start: raw_start < 0,
                    clipped_end: raw_end > day_count - 1,
                });
            }
        }
    }
    let lane_ends = first_fit(&spans);
    let bars: Vec<Bar> = spans
        .iter()
        .zip(lane_ends)
        .map(|(span, lane)| Bar {
            task_index: span.task_index,
            start_index: span.start_index,
            end_index: span.end_index,
            lane,
            clipped_start: span.clipped_start,
            clipped_end: span.clipped_end,
        })
        .collect();
    let task_count = bars.len();
    let in_progress_count = indices
        .iter()
        .filter(|index| snapshot.tasks[**index].status == Status::InProgress)
        .count();
    let urgent_count = indices
        .iter()
        .filter(|index| snapshot.tasks[**index].priority == Priority::Urgent)
        .count();
    PersonRow {
        id,
        name,
        role_label,
        task_count,
        in_progress_count,
        urgent_count,
        bars,
    }
}

/// First-fit lane assignment.
///
/// A span reuses lane `n` only when that lane ends before the span starts, so
/// bars never overlap inside one row.
fn first_fit(spans: &[Span]) -> Vec<usize> {
    let mut lane_ends: Vec<i64> = Vec::new();
    let mut lanes = Vec::with_capacity(spans.len());
    for span in spans {
        let lane = lane_ends
            .iter()
            .position(|lane_end| *lane_end < span.start_index);
        match lane {
            Some(lane) => {
                lane_ends[lane] = span.end_index;
                lanes.push(lane);
            }
            None => {
                lane_ends.push(span.end_index);
                lanes.push(lane_ends.len() - 1);
            }
        }
    }
    lanes
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::parse;

    const MONDAY: (i32, u32, u32) = (2026, 11, 23);

    fn monday() -> NaiveDate {
        NaiveDate::from_ymd_opt(MONDAY.0, MONDAY.1, MONDAY.2).expect("valid date")
    }

    fn snapshot(tasks: &str, members: &str) -> Snapshot {
        let json = format!(
            r#"{{"project":{{"name":"P","current_revision":1}},"members":[{members}],"tasks":[{tasks}]}}"#
        );
        parse(&json).expect("snapshot parses")
    }

    fn task(
        id: &str,
        status: &str,
        priority: &str,
        assignee: &str,
        start: &str,
        end: &str,
    ) -> String {
        format!(
            r#"{{"id":"{id}","title":"{id}","status":"{status}","priority":"{priority}","assignee_ids":[{assignee}],"planned_on":"{start}","starts_on":"{start}","due_on":"{end}"}}"#
        )
    }

    #[test]
    fn week_starts_on_monday() {
        let monday = monday();
        assert_eq!(week_start(monday), monday);
        let sunday = monday + Duration::days(6);
        assert_eq!(week_start(sunday), monday);
        assert_eq!(week_days(monday).len(), 7);
        assert_eq!(week_days(monday)[6], sunday);
    }

    #[test]
    fn span_prefers_explicit_dates_and_swaps_inverted_ranges() {
        let json = r#"{"project":{"name":"P"},"tasks":[
            {"id":"a","title":"A","status":"todo","priority":"low","planned_on":"2026-11-25"},
            {"id":"b","title":"B","status":"todo","priority":"low","planned_on":"2026-11-25","starts_on":"2026-11-23"},
            {"id":"c","title":"C","status":"todo","priority":"low","planned_on":"2026-11-25","due_on":"2026-11-27"},
            {"id":"d","title":"D","status":"todo","priority":"low","planned_on":"2026-11-25","starts_on":"2026-11-27","due_on":"2026-11-23"}
        ]}"#;
        let snapshot = parse(json).expect("snapshot parses");
        let day = |value: &str| parse_date(value).expect("valid date");
        assert_eq!(
            schedule_span(&snapshot.tasks[0]),
            Some((day("2026-11-25"), day("2026-11-25")))
        );
        assert_eq!(
            schedule_span(&snapshot.tasks[1]),
            Some((day("2026-11-23"), day("2026-11-25")))
        );
        assert_eq!(
            schedule_span(&snapshot.tasks[2]),
            Some((day("2026-11-25"), day("2026-11-27")))
        );
        assert_eq!(
            schedule_span(&snapshot.tasks[3]),
            Some((day("2026-11-23"), day("2026-11-27")))
        );
    }

    #[test]
    fn bars_clip_to_the_window() {
        let tasks = [
            task(
                "inside",
                "todo",
                "low",
                r#""u1""#,
                "2026-11-24",
                "2026-11-25",
            ),
            task("left", "todo", "low", r#""u1""#, "2026-11-20", "2026-11-24"),
            task(
                "right",
                "todo",
                "low",
                r#""u1""#,
                "2026-11-27",
                "2026-12-02",
            ),
            task(
                "outside",
                "todo",
                "low",
                r#""u1""#,
                "2026-12-10",
                "2026-12-11",
            ),
        ];
        let snapshot = snapshot(&tasks.join(","), r#"{"user_id":"u1","display_name":"Mia"}"#);
        let rows = build_rows(&snapshot, monday(), 7);
        assert_eq!(rows.len(), 1);
        let bars = &rows[0].bars;
        assert_eq!(bars.len(), 3);
        let inside = &bars[0];
        assert_eq!((inside.start_index, inside.end_index), (1, 2));
        assert!(!inside.clipped_start && !inside.clipped_end);
        let left = &bars[1];
        assert_eq!((left.start_index, left.end_index), (0, 1));
        assert!(left.clipped_start);
        let right = &bars[2];
        assert_eq!((right.start_index, right.end_index), (4, 6));
        assert!(right.clipped_end);
    }

    #[test]
    fn overlapping_bars_use_separate_lanes() {
        let tasks = [
            task("a", "todo", "urgent", r#""u1""#, "2026-11-23", "2026-11-25"),
            task("b", "todo", "high", r#""u1""#, "2026-11-24", "2026-11-26"),
            task("c", "todo", "medium", r#""u1""#, "2026-11-26", "2026-11-27"),
        ];
        let snapshot = snapshot(&tasks.join(","), r#"{"user_id":"u1","display_name":"Mia"}"#);
        let rows = build_rows(&snapshot, monday(), 7);
        let bars = &rows[0].bars;
        assert_eq!(bars[0].lane, 0);
        assert_eq!(bars[1].lane, 1);
        assert_eq!(bars[2].lane, 0, "lane 0 ends on day 2, so it is free again");
    }

    #[test]
    fn rows_order_by_priority_then_status() {
        let tasks = [
            task(
                "low",
                "in_progress",
                "low",
                r#""u1""#,
                "2026-11-23",
                "2026-11-23",
            ),
            task(
                "urgent-done",
                "done",
                "urgent",
                r#""u1""#,
                "2026-11-24",
                "2026-11-24",
            ),
            task(
                "urgent-open",
                "in_progress",
                "urgent",
                r#""u1""#,
                "2026-11-25",
                "2026-11-25",
            ),
            task(
                "high",
                "todo",
                "high",
                r#""u1""#,
                "2026-11-26",
                "2026-11-26",
            ),
        ];
        let snapshot = snapshot(&tasks.join(","), r#"{"user_id":"u1","display_name":"Mia"}"#);
        let rows = build_rows(&snapshot, monday(), 7);
        let titles: Vec<&str> = rows[0]
            .bars
            .iter()
            .map(|bar| snapshot.tasks[bar.task_index].title.as_str())
            .collect();
        assert_eq!(titles, vec!["urgent-open", "urgent-done", "high", "low"]);
    }

    #[test]
    fn unassigned_row_collects_orphan_tasks() {
        let tasks = [
            task("mine", "todo", "low", r#""u1""#, "2026-11-23", "2026-11-23"),
            task("orphan", "todo", "high", " ", "2026-11-24", "2026-11-24"),
        ];
        let snapshot = snapshot(&tasks.join(","), r#"{"user_id":"u1","display_name":"Mia"}"#);
        let rows = build_rows(&snapshot, monday(), 7);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[1].id, UNASSIGNED_ID);
        assert_eq!(rows[1].task_count, 1);
    }

    #[test]
    fn colors_match_the_spec() {
        assert_eq!(priority_color(Priority::Urgent), 0xD9_2D_3A);
        assert_eq!(priority_color(Priority::High), 0xFF_C4_00);
        assert_eq!(priority_color(Priority::Medium), 0x00_66_FF);
        assert_eq!(priority_color(Priority::Low), 0x5F_63_68);
        assert_eq!(status_color(Status::Todo), 0x8E_8E_93);
        assert_eq!(status_color(Status::InProgress), 0x0A_84_FF);
        assert_eq!(status_color(Status::Blocked), 0xFF_45_3A);
        assert_eq!(status_color(Status::Done), 0x30_D1_58);
    }

    #[test]
    fn row_counts_follow_visible_tasks() {
        let tasks = [
            task(
                "a",
                "in_progress",
                "urgent",
                r#""u1""#,
                "2026-11-23",
                "2026-11-23",
            ),
            task("b", "todo", "urgent", r#""u1""#, "2026-11-24", "2026-11-24"),
            task("c", "done", "low", r#""u1""#, "2026-12-20", "2026-12-20"),
        ];
        let snapshot = snapshot(&tasks.join(","), r#"{"user_id":"u1","display_name":"Mia"}"#);
        let rows = build_rows(&snapshot, monday(), 7);
        assert_eq!(rows[0].task_count, 2);
        assert_eq!(rows[0].in_progress_count, 1);
        assert_eq!(rows[0].urgent_count, 2);
    }
}
