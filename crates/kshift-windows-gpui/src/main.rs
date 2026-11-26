//! Kshift Windows Preview client shell.
//!
//! The shell renders a people schedule and a typed task editor. All business
//! data and writes come from `kshift-ffi`; this file owns presentation and
//! temporary UI state only.

use std::sync::Arc;
use std::time::Duration;

use chrono::NaiveDate;
use gpui::prelude::*;
use gpui::{
    div, px, rgb, size, App, Application, Bounds, Context, FocusHandle, Focusable, IntoElement,
    KeyDownEvent, MouseButton, Render, SharedString, Window, WindowBounds, WindowOptions,
};
use kshift_ffi::host::HostClient;
use kshift_windows::editing::{
    self, CommandFailure, CommandIds, CommandOutcome, DataSource, TaskDraft, TextField,
};
use kshift_windows::model::{self, Member, Priority, Snapshot, Status};
use kshift_windows::schedule::{self, PersonRow};

const NAME_WIDTH: f32 = 196.0;
const DAY_WIDTH: f32 = 116.0;
const BAR_HEIGHT: f32 = 30.0;
const LANE_STEP: f32 = 38.0;
const ROW_PADDING: f32 = 12.0;
const BAR_INSET: f32 = 8.0;
const MIN_ROW_HEIGHT: f32 = 72.0;
const DAY_COUNT: i64 = 7;
const WINDOW_WIDTH: f32 = 1280.0;
const WINDOW_HEIGHT: f32 = 800.0;

const BG: u32 = 0x0F_11_15;
const PANEL: u32 = 0x17_1A_21;
const EDITOR_PANEL: u32 = 0x1B_20_29;
const HEADER: u32 = 0x1F_24_30;
const WEEKEND: u32 = 0x1A_1F_2A;
const BORDER: u32 = 0x2C_33_42;
const TEXT: u32 = 0xE6_E8_EE;
const MUTED: u32 = 0x9A_A1_B0;
const ACCENT: u32 = 0x0A_84_FF;
const SUCCESS: u32 = 0x30_D1_58;
const WARNING: u32 = 0xFF_C4_00;

struct ServerSession {
    client: Arc<HostClient>,
    project_id: String,
}

struct LoadedSnapshot {
    snapshot: Snapshot,
    server: Option<ServerSession>,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
enum RefreshPurpose {
    KeepDraft,
    CloseAfterCommit,
}

#[derive(Debug, Clone, Eq, PartialEq)]
enum EditorStatus {
    Idle,
    Saving,
    SaveFailed(String),
    Conflict(CommandFailure),
    Refreshing,
    RefreshRequired {
        committed_revision: u64,
        message: String,
    },
    ReadyAfterRefresh(String),
    Blocked(String),
}

struct EditorState {
    task_id: String,
    expected_project_revision: u64,
    draft: TaskDraft,
    editable: bool,
    field: TextField,
    cursor: usize,
    client_id: String,
    status: EditorStatus,
}

impl EditorState {
    fn new(
        task: &model::Task,
        expected_project_revision: u64,
        editable: bool,
        client_id: String,
    ) -> Self {
        Self {
            task_id: task.id.clone(),
            expected_project_revision,
            draft: TaskDraft::from_task(task),
            editable,
            field: TextField::Title,
            cursor: task.title.len(),
            client_id,
            status: EditorStatus::Idle,
        }
    }

    fn busy(&self) -> bool {
        matches!(self.status, EditorStatus::Saving | EditorStatus::Refreshing)
    }

    fn input_enabled(&self) -> bool {
        self.editable && !self.busy()
    }

    fn can_save(&self) -> bool {
        self.editable
            && matches!(
                self.status,
                EditorStatus::Idle
                    | EditorStatus::SaveFailed(_)
                    | EditorStatus::ReadyAfterRefresh(_)
            )
    }

    fn focus_field(&mut self, field: TextField) {
        self.field = field;
        self.cursor = self.draft.text_field(field).len();
    }

    fn text_value(&self) -> &str {
        self.draft.text_field(self.field)
    }

    fn text_value_mut(&mut self) -> &mut String {
        self.draft.text_field_mut(self.field)
    }

    fn insert(&mut self, text: &str) {
        let mut cursor = self.cursor;
        editing::insert_text(self.text_value_mut(), &mut cursor, text);
        self.cursor = cursor;
    }

    fn backspace(&mut self) {
        let mut cursor = self.cursor;
        editing::backspace(self.text_value_mut(), &mut cursor);
        self.cursor = cursor;
    }

    fn delete(&mut self) {
        let mut cursor = self.cursor;
        editing::delete(self.text_value_mut(), &mut cursor);
        self.cursor = cursor;
    }

    fn move_left(&mut self) {
        let value = self.text_value().to_owned();
        editing::move_left(&value, &mut self.cursor);
    }

    fn move_right(&mut self) {
        let value = self.text_value().to_owned();
        editing::move_right(&value, &mut self.cursor);
    }

    fn move_home(&mut self) {
        editing::move_home(&mut self.cursor);
    }

    fn move_end(&mut self) {
        self.cursor = self.text_value().len();
    }

    fn next_field(&mut self) {
        self.focus_field(self.field.next());
    }
}

enum SaveWorkerResult {
    Committed {
        task_id: String,
        outcome: CommandOutcome,
        snapshot: Result<Snapshot, String>,
    },
    Rejected {
        task_id: String,
        failure: CommandFailure,
    },
}

struct RefreshWorkerResult {
    task_id: String,
    purpose: RefreshPurpose,
    snapshot: Result<Snapshot, String>,
}

struct ScheduleView {
    title: SharedString,
    subtitle: SharedString,
    days: Vec<NaiveDate>,
    rows: Vec<PersonRow>,
    tasks: Vec<model::Task>,
    members: Vec<Member>,
    current_revision: u64,
    source: DataSource,
    server: Option<ServerSession>,
    client_id: String,
    notice: Option<String>,
    error: Option<String>,
    editor: Option<EditorState>,
    focus_handle: FocusHandle,
}

impl ScheduleView {
    fn from_loaded(loaded: LoadedSnapshot, anchor: NaiveDate, focus_handle: FocusHandle) -> Self {
        let window_start = schedule::week_start(anchor);
        let days = schedule::week_days(window_start);
        let rows = schedule::build_rows(&loaded.snapshot, window_start, DAY_COUNT);
        let source = if loaded.server.is_some() {
            DataSource::Server
        } else {
            DataSource::Fixture
        };
        let subtitle: SharedString = format!(
            "Revision {} · {} · 周 {} 至 {}",
            loaded.snapshot.project.current_revision,
            source.label(),
            schedule::date_label(days[0]),
            schedule::date_label(days[6])
        )
        .into();
        Self {
            title: loaded.snapshot.project.name.clone().into(),
            subtitle,
            days,
            rows,
            tasks: loaded.snapshot.tasks.clone(),
            members: loaded.snapshot.members.clone(),
            current_revision: loaded.snapshot.project.current_revision,
            source,
            server: loaded.server,
            client_id: CommandIds::client_id(),
            notice: None,
            error: None,
            editor: None,
            focus_handle,
        }
    }

    fn error(message: String, focus_handle: FocusHandle) -> Self {
        Self {
            title: "Kshift".into(),
            subtitle: "无法加载快照".into(),
            days: schedule::week_days(schedule::week_start(chrono::Local::now().date_naive())),
            rows: Vec::new(),
            tasks: Vec::new(),
            members: Vec::new(),
            current_revision: 0,
            source: DataSource::Fixture,
            server: None,
            client_id: CommandIds::client_id(),
            notice: None,
            error: Some(message),
            editor: None,
            focus_handle,
        }
    }

    fn open_editor_by_id(&mut self, task_id: &str) {
        let Some(task) = self.tasks.iter().find(|task| task.id == task_id).cloned() else {
            self.notice = Some(format!("找不到任务 {task_id}"));
            return;
        };
        self.editor = Some(EditorState::new(
            &task,
            self.current_revision,
            self.source.can_edit(),
            self.client_id.clone(),
        ));
        self.notice = None;
    }

    fn open_editor(&mut self, task_id: String, window: &mut Window, cx: &mut Context<Self>) {
        self.open_editor_by_id(&task_id);
        self.focus_handle.focus(window);
        if let Some(editor) = &self.editor {
            println!(
                "kshift-windows: editor opened task={} revision={} version={} editable={}",
                editor.task_id,
                editor.expected_project_revision,
                editor.draft.expected_entity_version,
                editor.editable
            );
        }
        cx.notify();
    }

    fn close_editor(&mut self, cx: &mut Context<Self>) {
        if self.editor.as_ref().is_some_and(EditorState::busy) {
            return;
        }
        self.editor = None;
        cx.notify();
    }

    fn install_snapshot(&mut self, snapshot: Snapshot) {
        let window_start = self
            .days
            .first()
            .copied()
            .unwrap_or_else(|| schedule::week_start(chrono::Local::now().date_naive()));
        self.days = schedule::week_days(window_start);
        self.rows = schedule::build_rows(&snapshot, window_start, DAY_COUNT);
        self.title = snapshot.project.name.clone().into();
        self.current_revision = snapshot.project.current_revision;
        self.members = snapshot.members.clone();
        self.tasks = snapshot.tasks.clone();
        self.subtitle = format!(
            "Revision {} · {} · 周 {} 至 {}",
            self.current_revision,
            self.source.label(),
            schedule::date_label(self.days[0]),
            schedule::date_label(self.days[6])
        )
        .into();
    }

    fn save_editor(&mut self, cx: &mut Context<Self>) {
        let Some(editor) = self.editor.as_mut() else {
            return;
        };
        if !editor.can_save() {
            return;
        }
        let Some(server) = &self.server else {
            editor.status = EditorStatus::Blocked("没有可写的 server session".to_owned());
            cx.notify();
            return;
        };
        let ids = CommandIds::next(&editor.client_id);
        let command_json = match editor.draft.update_command_json(
            &server.project_id,
            editor.expected_project_revision,
            &ids.client_id,
            &ids.command_id,
        ) {
            Ok(json) => json,
            Err(error) => {
                editor.status = EditorStatus::SaveFailed(error);
                cx.notify();
                return;
            }
        };
        let client = server.client.clone();
        let project_id = server.project_id.clone();
        let task_id = editor.task_id.clone();
        editor.status = EditorStatus::Saving;

        let task = cx.spawn(async move |view, cx| {
            let result = cx
                .background_spawn(async move {
                    match client.execute_command_json(&command_json) {
                        Ok(value) => match CommandOutcome::parse(&value) {
                            Ok(outcome) => {
                                let snapshot = client.snapshot_json(&project_id).and_then(|json| {
                                    model::parse(&json)
                                        .map_err(|error| format!("parse ffi snapshot: {error}"))
                                });
                                SaveWorkerResult::Committed {
                                    task_id,
                                    outcome,
                                    snapshot,
                                }
                            }
                            Err(error) => SaveWorkerResult::Rejected {
                                task_id,
                                failure: CommandFailure {
                                    code: "protocol_error".to_owned(),
                                    message: error,
                                    retryable: false,
                                    current_revision: None,
                                    entity_id: None,
                                    entity_version: None,
                                },
                            },
                        },
                        Err(error) => SaveWorkerResult::Rejected {
                            task_id,
                            failure: CommandFailure::parse(&error),
                        },
                    }
                })
                .await;
            let _ = view.update(cx, |this, cx| {
                this.complete_save(result);
                cx.notify();
            });
        });
        task.detach();
        cx.notify();
    }

    fn complete_save(&mut self, result: SaveWorkerResult) {
        match result {
            SaveWorkerResult::Committed {
                task_id,
                outcome,
                snapshot,
            } => {
                if self
                    .editor
                    .as_ref()
                    .is_none_or(|editor| editor.task_id != task_id)
                {
                    return;
                }
                match snapshot {
                    Ok(snapshot) => {
                        self.install_snapshot(snapshot);
                        self.editor = None;
                        self.notice = Some(format!(
                            "已保存任务 · Revision {} · Command {}",
                            outcome.revision, outcome.command_id
                        ));
                        println!(
                            "kshift-windows: save committed task={} revision={} command={}",
                            task_id, outcome.revision, outcome.command_id
                        );
                    }
                    Err(message) => {
                        if let Some(editor) = self.editor.as_mut() {
                            editor.status = EditorStatus::RefreshRequired {
                                committed_revision: outcome.revision,
                                message: format!("保存已提交，但刷新快照失败：{message}"),
                            };
                        }
                    }
                }
            }
            SaveWorkerResult::Rejected { task_id, failure } => {
                let Some(editor) = self.editor.as_mut() else {
                    return;
                };
                if editor.task_id != task_id {
                    return;
                }
                if failure.is_conflict() {
                    println!(
                        "kshift-windows: save conflict task={} current_revision={:?} current_entity_version={:?} draft_preserved=true",
                        task_id, failure.current_revision, failure.entity_version
                    );
                    editor.status = EditorStatus::Conflict(failure);
                } else {
                    eprintln!(
                        "kshift-windows: save failed task={} code={} message={}",
                        task_id, failure.code, failure.message
                    );
                    editor.status = EditorStatus::SaveFailed(failure.message);
                }
            }
        }
    }

    fn refresh_editor(&mut self, purpose: RefreshPurpose, cx: &mut Context<Self>) {
        let Some(editor) = self.editor.as_mut() else {
            return;
        };
        if editor.busy() {
            return;
        }
        let Some(server) = &self.server else {
            editor.status = EditorStatus::Blocked("没有可刷新的 server session".to_owned());
            cx.notify();
            return;
        };
        let client = server.client.clone();
        let project_id = server.project_id.clone();
        let task_id = editor.task_id.clone();
        editor.status = EditorStatus::Refreshing;

        let task = cx.spawn(async move |view, cx| {
            let result = cx
                .background_spawn(async move {
                    let snapshot = client.snapshot_json(&project_id).and_then(|json| {
                        model::parse(&json).map_err(|error| format!("parse ffi snapshot: {error}"))
                    });
                    RefreshWorkerResult {
                        task_id,
                        purpose,
                        snapshot,
                    }
                })
                .await;
            let _ = view.update(cx, |this, cx| {
                this.complete_refresh(result);
                cx.notify();
            });
        });
        task.detach();
        cx.notify();
    }

    fn complete_refresh(&mut self, result: RefreshWorkerResult) {
        let Some(editor) = self.editor.as_ref() else {
            return;
        };
        if editor.task_id != result.task_id {
            return;
        }
        match result.snapshot {
            Ok(snapshot) => match result.purpose {
                RefreshPurpose::CloseAfterCommit => {
                    let revision = snapshot.project.current_revision;
                    self.install_snapshot(snapshot);
                    self.editor = None;
                    self.notice = Some(format!("已刷新到 Revision {revision}"));
                }
                RefreshPurpose::KeepDraft => {
                    let task_id = result.task_id;
                    let Some(latest) = snapshot
                        .tasks
                        .iter()
                        .find(|task| task.id == task_id)
                        .cloned()
                    else {
                        if let Some(editor) = self.editor.as_mut() {
                            editor.status =
                                EditorStatus::Blocked("任务已被删除或已无权限读取".to_owned());
                        }
                        return;
                    };
                    let revision = snapshot.project.current_revision;
                    let version = latest.version;
                    self.install_snapshot(snapshot);
                    if let Some(editor) = self.editor.as_mut() {
                        editor.expected_project_revision = revision;
                        editor.draft.expected_entity_version = version;
                        editor.status = EditorStatus::ReadyAfterRefresh(format!(
                            "已刷新到 Revision {revision} · Version {version}；草稿已保留，请确认后再次保存。"
                        ));
                    }
                }
            },
            Err(message) => {
                if let Some(editor) = self.editor.as_mut() {
                    editor.status = EditorStatus::Blocked(format!("刷新失败：{message}"));
                }
            }
        }
    }

    fn on_key_down(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        if self.editor.is_none() {
            return;
        }
        let key = event.keystroke.key.as_str();
        if key == "escape" {
            self.close_editor(cx);
            return;
        }
        if event.keystroke.modifiers.secondary() && key.eq_ignore_ascii_case("s") {
            self.save_editor(cx);
            return;
        }
        if event.keystroke.modifiers.secondary() && key.eq_ignore_ascii_case("v") {
            if let Some(text) = cx.read_from_clipboard().and_then(|item| item.text()) {
                if let Some(editor) = self.editor.as_mut() {
                    if editor.input_enabled() {
                        editor.insert(&text);
                        cx.notify();
                    }
                }
            }
            return;
        }
        let Some(editor) = self.editor.as_mut() else {
            return;
        };
        if !editor.input_enabled() {
            return;
        }
        match key {
            "backspace" => editor.backspace(),
            "delete" => editor.delete(),
            "left" => editor.move_left(),
            "right" => editor.move_right(),
            "home" => editor.move_home(),
            "end" => editor.move_end(),
            "tab" => editor.next_field(),
            "enter" => {
                if editor.field == TextField::Description {
                    editor.insert("\n");
                } else if editor.field == TextField::Title {
                    editor.focus_field(TextField::Description);
                }
            }
            _ => {
                if !event.keystroke.modifiers.control
                    && !event.keystroke.modifiers.alt
                    && !event.keystroke.modifiers.platform
                {
                    if let Some(text) = &event.keystroke.key_char {
                        editor.insert(text);
                    }
                }
            }
        }
        self.focus_handle.focus(window);
        cx.notify();
    }

    fn render_header(&self) -> impl IntoElement {
        div().flex().items_center().gap_4().child(
            div()
                .flex()
                .flex_col()
                .gap_1()
                .child(
                    div()
                        .text_xl()
                        .text_color(rgb(TEXT))
                        .child(self.title.clone()),
                )
                .child(
                    div()
                        .text_sm()
                        .text_color(rgb(MUTED))
                        .child(self.subtitle.clone()),
                ),
        )
    }

    fn render_day_headers(&self) -> impl IntoElement {
        let mut row = div()
            .flex()
            .h(px(44.0))
            .border_b_1()
            .border_color(rgb(BORDER))
            .child(
                div()
                    .w(px(NAME_WIDTH))
                    .text_sm()
                    .text_color(rgb(MUTED))
                    .child("成员"),
            );
        for (index, day) in self.days.iter().enumerate() {
            let weekend = index >= 5;
            let mut cell = div()
                .flex()
                .flex_col()
                .w(px(DAY_WIDTH))
                .justify_center()
                .child(
                    div()
                        .text_sm()
                        .text_color(rgb(TEXT))
                        .child(schedule::weekday_label(*day)),
                )
                .child(
                    div()
                        .text_sm()
                        .text_color(rgb(MUTED))
                        .child(schedule::date_label(*day)),
                );
            if weekend {
                cell = cell.bg(rgb(WEEKEND));
            }
            row = row.child(cell);
        }
        row
    }

    fn render_row(&self, row: &PersonRow, cx: &mut Context<Self>) -> impl IntoElement {
        let lanes = row.bars.iter().map(|bar| bar.lane + 1).max().unwrap_or(1);
        let height = (ROW_PADDING * 2.0 + LANE_STEP * lanes as f32).max(MIN_ROW_HEIGHT);
        let name = SharedString::from(row.name.clone());
        let role = SharedString::from(row.role_label.clone());
        let counts = SharedString::from(format!(
            "{} 项 · 进行中 {} · P0 {}",
            row.task_count, row.in_progress_count, row.urgent_count
        ));

        let mut timeline = div()
            .relative()
            .flex()
            .h(px(height))
            .w(px(DAY_WIDTH * DAY_COUNT as f32));
        for index in 0..DAY_COUNT {
            let mut cell = div().w(px(DAY_WIDTH)).h(px(height));
            if index >= 5 {
                cell = cell.bg(rgb(WEEKEND));
            }
            timeline = timeline.child(cell);
        }
        for bar in &row.bars {
            let task = &self.tasks[bar.task_index];
            let color = schedule::priority_color(task.priority);
            let width = (bar.day_count() as f32 * DAY_WIDTH - BAR_INSET * 2.0).max(32.0);
            let left = bar.start_index as f32 * DAY_WIDTH + BAR_INSET;
            let top = ROW_PADDING + bar.lane as f32 * LANE_STEP;
            let task_id = task.id.clone();
            timeline = timeline.child(
                div()
                    .absolute()
                    .left(px(left))
                    .top(px(top))
                    .w(px(width))
                    .h(px(BAR_HEIGHT))
                    .flex()
                    .items_center()
                    .gap_2()
                    .px_2()
                    .rounded_md()
                    .bg(rgb(color))
                    .text_sm()
                    .text_color(rgb(text_on(color)))
                    .overflow_hidden()
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(move |this, _event, window, cx| {
                            this.open_editor(task_id.clone(), window, cx);
                        }),
                    )
                    .child(schedule::status_glyph(task.status))
                    .child(SharedString::from(task.title.clone()))
                    .child(SharedString::from(task.priority.badge())),
            );
        }

        div()
            .flex()
            .h(px(height))
            .border_b_1()
            .border_color(rgb(BORDER))
            .child(
                div()
                    .flex()
                    .flex_col()
                    .w(px(NAME_WIDTH))
                    .p_2()
                    .gap_1()
                    .child(div().text_sm().text_color(rgb(TEXT)).child(name))
                    .child(div().text_sm().text_color(rgb(MUTED)).child(role))
                    .child(div().text_sm().text_color(rgb(MUTED)).child(counts)),
            )
            .child(timeline)
    }

    fn render_text_field(
        &self,
        label: &'static str,
        field: TextField,
        editor: &EditorState,
        multiline: bool,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let value = editor.draft.text_field(field).to_owned();
        let focused = editor.field == field && editor.input_enabled();
        let (content, color) = if focused {
            let (before, after) = editing::cursor_parts(&value, editor.cursor);
            (format!("{before}│{after}"), TEXT)
        } else if value.is_empty() {
            (
                match field {
                    TextField::Title => "任务标题".to_owned(),
                    TextField::Description => "Markdown 说明".to_owned(),
                    TextField::PlannedOn => "YYYY-MM-DD".to_owned(),
                },
                MUTED,
            )
        } else {
            (value, TEXT)
        };

        let mut input = div()
            .w_full()
            .min_h(px(if multiline { 112.0 } else { 38.0 }))
            .p_2()
            .rounded_md()
            .border_1()
            .border_color(rgb(if focused { ACCENT } else { BORDER }))
            .bg(rgb(BG))
            .text_sm()
            .line_height(px(21.0))
            .whitespace_normal()
            .text_color(rgb(color))
            .child(SharedString::from(content));
        if editor.input_enabled() {
            input = input.on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, _event, window, cx| {
                    if let Some(editor) = this.editor.as_mut() {
                        editor.focus_field(field);
                    }
                    this.focus_handle.focus(window);
                    cx.notify();
                }),
            );
        }

        div()
            .flex()
            .flex_col()
            .gap_1()
            .w_full()
            .child(div().text_sm().text_color(rgb(MUTED)).child(label))
            .child(input)
    }

    fn render_status_selector(
        &self,
        editor: &EditorState,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let mut row = div().flex().flex_wrap().gap_2();
        for status in [
            Status::Todo,
            Status::InProgress,
            Status::Blocked,
            Status::Done,
        ] {
            let selected = editor.draft.status == status;
            let color = if selected {
                schedule::status_color(status)
            } else {
                HEADER
            };
            let text = if selected { text_on(color) } else { TEXT };
            let mut button = div()
                .px_2()
                .py_1()
                .rounded_md()
                .border_1()
                .border_color(rgb(if selected { color } else { BORDER }))
                .bg(rgb(color))
                .text_sm()
                .text_color(rgb(text))
                .child(status.label());
            if editor.input_enabled() {
                button = button.on_mouse_down(
                    MouseButton::Left,
                    cx.listener(move |this, _event, _window, cx| {
                        if let Some(editor) = this.editor.as_mut() {
                            editor.draft.status = status;
                        }
                        cx.notify();
                    }),
                );
            }
            row = row.child(button);
        }
        row
    }

    fn render_priority_selector(
        &self,
        editor: &EditorState,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let mut row = div().flex().flex_wrap().gap_2();
        for priority in [
            Priority::Urgent,
            Priority::High,
            Priority::Medium,
            Priority::Low,
        ] {
            let selected = editor.draft.priority == priority;
            let color = if selected {
                schedule::priority_color(priority)
            } else {
                HEADER
            };
            let text = if selected { text_on(color) } else { TEXT };
            let mut button = div()
                .px_2()
                .py_1()
                .rounded_md()
                .border_1()
                .border_color(rgb(if selected { color } else { BORDER }))
                .bg(rgb(color))
                .text_sm()
                .text_color(rgb(text))
                .child(priority.badge());
            if editor.input_enabled() {
                button = button.on_mouse_down(
                    MouseButton::Left,
                    cx.listener(move |this, _event, _window, cx| {
                        if let Some(editor) = this.editor.as_mut() {
                            editor.draft.priority = priority;
                        }
                        cx.notify();
                    }),
                );
            }
            row = row.child(button);
        }
        row
    }

    fn render_assignees(&self, editor: &EditorState, cx: &mut Context<Self>) -> impl IntoElement {
        let mut row = div().flex().flex_wrap().gap_2();
        if self.members.is_empty() {
            row = row.child(div().text_sm().text_color(rgb(MUTED)).child("无项目成员"));
        }
        for member in &self.members {
            let selected = editor.draft.assignee_ids.contains(&member.user_id);
            let color = if selected { ACCENT } else { HEADER };
            let text = if selected { text_on(color) } else { TEXT };
            let user_id = member.user_id.clone();
            let label = format!("{} · {}", member.display_name, member.role.label());
            let mut button = div()
                .px_2()
                .py_1()
                .rounded_md()
                .border_1()
                .border_color(rgb(if selected { color } else { BORDER }))
                .bg(rgb(color))
                .text_sm()
                .text_color(rgb(text))
                .child(SharedString::from(label));
            if editor.input_enabled() {
                button = button.on_mouse_down(
                    MouseButton::Left,
                    cx.listener(move |this, _event, _window, cx| {
                        if let Some(editor) = this.editor.as_mut() {
                            editor.draft.toggle_assignee(&user_id);
                        }
                        cx.notify();
                    }),
                );
            }
            row = row.child(button);
        }
        row
    }

    fn render_editor(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let Some(editor) = &self.editor else {
            return div();
        };
        let busy = editor.busy();
        let can_save = editor.can_save();
        let title = if editor.editable {
            "编辑任务"
        } else {
            "任务详情 · 只读"
        };
        let meta = format!(
            "Project revision {} · Task version {} · {}",
            editor.expected_project_revision, editor.draft.expected_entity_version, editor.task_id
        );

        let close = {
            let mut button = div()
                .px_2()
                .py_1()
                .rounded_md()
                .border_1()
                .border_color(rgb(BORDER))
                .text_sm()
                .text_color(rgb(TEXT))
                .child("关闭");
            if !busy {
                button = button.on_mouse_down(
                    MouseButton::Left,
                    cx.listener(|this, _event, _window, cx| this.close_editor(cx)),
                );
            }
            button
        };

        let mut footer = div().flex().items_center().gap_2().w_full();
        let mut footer_status = div().flex().flex_col().gap_1().flex_1();
        match &editor.status {
            EditorStatus::Idle => {}
            EditorStatus::Saving => {
                footer_status =
                    footer_status.child(div().text_sm().text_color(rgb(ACCENT)).child("正在保存…"));
            }
            EditorStatus::SaveFailed(message) => {
                footer_status = footer_status.child(
                    div()
                        .text_sm()
                        .text_color(rgb(schedule::STATUS_BLOCKED))
                        .child(SharedString::from(message.clone())),
                );
            }
            EditorStatus::Conflict(failure) => {
                let revision = failure
                    .current_revision
                    .map(|value| value.to_string())
                    .unwrap_or_else(|| "未知".to_owned());
                let version = failure
                    .entity_version
                    .map(|value| value.to_string())
                    .unwrap_or_else(|| "未知".to_owned());
                footer_status = footer_status
                    .child(
                        div()
                            .text_sm()
                            .text_color(rgb(schedule::STATUS_BLOCKED))
                            .child("版本冲突：未覆盖服务器数据。"),
                    )
                    .child(
                        div()
                            .text_sm()
                            .text_color(rgb(WARNING))
                            .child(SharedString::from(format!(
                                "最新 Revision {revision} · Version {version}。刷新后草稿仍会保留。"
                            ))),
                    );
                footer = footer.child(
                    div()
                        .px_2()
                        .py_1()
                        .rounded_md()
                        .bg(rgb(WARNING))
                        .text_sm()
                        .text_color(rgb(text_on(WARNING)))
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(|this, _event, _window, cx| {
                                this.refresh_editor(RefreshPurpose::KeepDraft, cx);
                            }),
                        )
                        .child("刷新并保留草稿"),
                );
            }
            EditorStatus::Refreshing => {
                footer_status = footer_status.child(
                    div()
                        .text_sm()
                        .text_color(rgb(ACCENT))
                        .child("正在刷新快照…"),
                );
            }
            EditorStatus::RefreshRequired {
                committed_revision,
                message,
            } => {
                footer_status = footer_status
                    .child(
                        div()
                            .text_sm()
                            .text_color(rgb(SUCCESS))
                            .child(SharedString::from(format!(
                                "Revision {committed_revision} 已提交。"
                            ))),
                    )
                    .child(
                        div()
                            .text_sm()
                            .text_color(rgb(WARNING))
                            .child(SharedString::from(message.clone())),
                    );
                footer = footer.child(
                    div()
                        .px_2()
                        .py_1()
                        .rounded_md()
                        .bg(rgb(WARNING))
                        .text_sm()
                        .text_color(rgb(text_on(WARNING)))
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(|this, _event, _window, cx| {
                                this.refresh_editor(RefreshPurpose::CloseAfterCommit, cx);
                            }),
                        )
                        .child("刷新并关闭"),
                );
            }
            EditorStatus::ReadyAfterRefresh(message) => {
                footer_status = footer_status.child(
                    div()
                        .text_sm()
                        .text_color(rgb(SUCCESS))
                        .child(SharedString::from(message.clone())),
                );
            }
            EditorStatus::Blocked(message) => {
                footer_status = footer_status.child(
                    div()
                        .text_sm()
                        .text_color(rgb(schedule::STATUS_BLOCKED))
                        .child(SharedString::from(message.clone())),
                );
            }
        }

        if editor.editable {
            let mut save = div()
                .px_3()
                .py_1()
                .rounded_md()
                .border_1()
                .border_color(rgb(if can_save { ACCENT } else { BORDER }))
                .bg(rgb(if can_save { ACCENT } else { HEADER }))
                .text_sm()
                .text_color(rgb(if can_save { 0xFF_FF_FF } else { MUTED }))
                .child("保存");
            if can_save {
                save = save.on_mouse_down(
                    MouseButton::Left,
                    cx.listener(|this, _event, _window, cx| this.save_editor(cx)),
                );
            }
            footer = footer.child(save);
        } else {
            footer = footer.child(
                div()
                    .text_sm()
                    .text_color(rgb(MUTED))
                    .child("fixture 模式只读；设置 KSHIFT_ENDPOINT 后可编辑。"),
            );
        }
        footer = footer.child(footer_status).child(close);

        div()
            .absolute()
            .right(px(24.0))
            .top(px(24.0))
            .w(px(430.0))
            .max_h(px(WINDOW_HEIGHT - 48.0))
            .flex()
            .flex_col()
            .gap_3()
            .p_4()
            .rounded_md()
            .border_1()
            .border_color(rgb(BORDER))
            .bg(rgb(EDITOR_PANEL))
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap_2()
                    .child(div().flex_1().text_lg().text_color(rgb(TEXT)).child(title))
                    .child(
                        div()
                            .text_sm()
                            .text_color(rgb(MUTED))
                            .child("Esc 关闭 · Ctrl+S 保存"),
                    ),
            )
            .child(
                div()
                    .text_sm()
                    .text_color(rgb(MUTED))
                    .child(SharedString::from(meta)),
            )
            .child(self.render_text_field("标题", TextField::Title, editor, false, cx))
            .child(self.render_text_field(
                "Markdown 说明",
                TextField::Description,
                editor,
                true,
                cx,
            ))
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap_1()
                    .child(div().text_sm().text_color(rgb(MUTED)).child("状态"))
                    .child(self.render_status_selector(editor, cx)),
            )
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap_1()
                    .child(div().text_sm().text_color(rgb(MUTED)).child("优先级"))
                    .child(self.render_priority_selector(editor, cx)),
            )
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap_1()
                    .child(div().text_sm().text_color(rgb(MUTED)).child("负责人"))
                    .child(self.render_assignees(editor, cx)),
            )
            .child(self.render_text_field("计划日期", TextField::PlannedOn, editor, false, cx))
            .child(
                div()
                    .border_t_1()
                    .border_color(rgb(BORDER))
                    .pt_3()
                    .child(footer),
            )
    }
}

impl Render for ScheduleView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let mut root = div()
            .relative()
            .flex()
            .flex_col()
            .size_full()
            .bg(rgb(BG))
            .p_6()
            .gap_4()
            .track_focus(&self.focus_handle)
            .on_key_down(cx.listener(Self::on_key_down))
            .child(self.render_header());
        if let Some(message) = &self.error {
            root = root.child(
                div()
                    .rounded_md()
                    .border_1()
                    .border_color(rgb(schedule::STATUS_BLOCKED))
                    .p_4()
                    .text_sm()
                    .text_color(rgb(TEXT))
                    .child(SharedString::from(message.clone())),
            );
            return root;
        }
        if let Some(notice) = &self.notice {
            root = root.child(
                div()
                    .rounded_md()
                    .border_1()
                    .border_color(rgb(SUCCESS))
                    .p_3()
                    .text_sm()
                    .text_color(rgb(TEXT))
                    .child(SharedString::from(notice.clone())),
            );
        }
        root = root
            .child(
                div()
                    .flex()
                    .flex_col()
                    .bg(rgb(PANEL))
                    .rounded_md()
                    .border_1()
                    .border_color(rgb(BORDER))
                    .child(
                        div()
                            .flex()
                            .h(px(32.0))
                            .items_center()
                            .px_2()
                            .bg(rgb(HEADER))
                            .text_sm()
                            .text_color(rgb(MUTED))
                            .child("人员 × 自然日期"),
                    )
                    .child(self.render_day_headers()),
            )
            .child(
                div()
                    .flex()
                    .flex_col()
                    .bg(rgb(PANEL))
                    .rounded_md()
                    .border_1()
                    .border_color(rgb(BORDER)),
            );
        let mut list = div().flex().flex_col();
        for row in &self.rows {
            list = list.child(self.render_row(row, cx));
        }
        root = root.child(list);
        if self.editor.is_some() {
            root = root.child(self.render_editor(cx));
        }
        root
    }
}

impl Focusable for ScheduleView {
    fn focus_handle(&self, _: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

fn text_on(background: u32) -> u32 {
    let red = (background >> 16) & 0xFF;
    let green = (background >> 8) & 0xFF;
    let blue = background & 0xFF;
    let luminance = (red * 299 + green * 587 + blue * 114) / 1000;
    if luminance > 160 {
        0x101216
    } else {
        0xFF_FF_FF
    }
}

#[derive(Default)]
struct CliArgs {
    snapshot: Option<String>,
    today: Option<NaiveDate>,
    open_task: Option<String>,
    smoke_edit: bool,
}

fn parse_args() -> CliArgs {
    let mut parsed = CliArgs::default();
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--snapshot" => parsed.snapshot = args.next(),
            "--today" => parsed.today = args.next().and_then(|value| schedule::parse_date(&value)),
            "--open-task" => parsed.open_task = args.next(),
            "--smoke-edit" => parsed.smoke_edit = true,
            other => parsed.snapshot = Some(other.to_owned()),
        }
    }
    parsed
}

fn load_snapshot(args: &CliArgs) -> Result<LoadedSnapshot, String> {
    if let Some(path) = &args.snapshot {
        return model::load(path).map(|snapshot| LoadedSnapshot {
            snapshot,
            server: None,
        });
    }
    if let Ok(path) = std::env::var("KSHIFT_SNAPSHOT") {
        return model::load(path).map(|snapshot| LoadedSnapshot {
            snapshot,
            server: None,
        });
    }
    if std::env::var("KSHIFT_ENDPOINT").is_ok() {
        return load_from_ffi();
    }
    Err("缺少数据源。使用 --snapshot <path>，或设置 KSHIFT_SNAPSHOT。".to_owned())
}

fn load_from_ffi() -> Result<LoadedSnapshot, String> {
    let endpoint = required_env("KSHIFT_ENDPOINT")?;
    let ca_path = required_env("KSHIFT_CA_PEM")?;
    let token = required_env("KSHIFT_TOKEN")?;
    let project_id = required_env("KSHIFT_PROJECT_ID")?;
    let ca = std::fs::read(&ca_path).map_err(|error| format!("read {ca_path}: {error}"))?;
    let client = Arc::new(kshift_ffi::host::HostClient::connect(
        &endpoint,
        ca,
        std::env::var("KSHIFT_TLS_DOMAIN").ok(),
        None,
    )?);
    client.set_token(&token)?;
    let json = client.snapshot_json(&project_id)?;
    let snapshot = model::parse(&json).map_err(|error| format!("parse ffi snapshot: {error}"))?;
    Ok(LoadedSnapshot {
        snapshot,
        server: Some(ServerSession { client, project_id }),
    })
}

fn required_env(name: &str) -> Result<String, String> {
    std::env::var(name).map_err(|_| format!("缺少环境变量 {name}"))
}

fn main() {
    if let Ok(seconds) = std::env::var("KSHIFT_SMOKE_SECONDS") {
        let seconds: u64 = seconds.parse().unwrap_or(3);
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_secs(seconds));
            println!("kshift-windows: smoke window alive; exiting");
            std::process::exit(0);
        });
    }

    let args = parse_args();
    let anchor = args
        .today
        .unwrap_or_else(|| chrono::Local::now().date_naive());
    let open_task = args.open_task.clone();
    let smoke_edit = args.smoke_edit
        || std::env::var("KSHIFT_SMOKE_EDIT")
            .is_ok_and(|value| matches!(value.as_str(), "1" | "true" | "yes"));
    let loaded = match load_snapshot(&args) {
        Ok(loaded) => {
            println!(
                "kshift-windows: snapshot loaded project={} tasks={} editable={}",
                loaded.snapshot.project.name,
                loaded.snapshot.tasks.len(),
                loaded.server.is_some()
            );
            loaded
        }
        Err(message) => {
            eprintln!("kshift-windows: {message}");
            Application::new().run(move |cx: &mut App| {
                let bounds = Bounds::centered(None, size(px(WINDOW_WIDTH), px(WINDOW_HEIGHT)), cx);
                cx.open_window(
                    WindowOptions {
                        window_bounds: Some(WindowBounds::Windowed(bounds)),
                        ..Default::default()
                    },
                    move |window, cx| {
                        let view =
                            cx.new(|cx| ScheduleView::error(message.clone(), cx.focus_handle()));
                        window.focus(&view.read(cx).focus_handle);
                        view
                    },
                )
                .expect("open window");
                cx.activate(true);
                println!("kshift-windows: window opened");
            });
            return;
        }
    };

    Application::new().run(move |cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(WINDOW_WIDTH), px(WINDOW_HEIGHT)), cx);
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                ..Default::default()
            },
            move |window, cx| {
                let view = cx.new(|cx| {
                    let mut view = ScheduleView::from_loaded(loaded, anchor, cx.focus_handle());
                    if let Some(task_id) = open_task.as_deref() {
                        view.open_editor_by_id(task_id);
                        if let Some(editor) = &view.editor {
                            println!(
                                "kshift-windows: editor opened at startup task={} editable={}",
                                editor.task_id, editor.editable
                            );
                        }
                    }
                    if smoke_edit {
                        if let Some(editor) = &mut view.editor {
                            editor.draft.title = format!("{} [smoke]", editor.draft.title);
                            editor.cursor = editor.draft.title.len();
                        }
                        view.save_editor(cx);
                    }
                    view
                });
                window.focus(&view.read(cx).focus_handle);
                view
            },
        )
        .expect("open window");
        cx.activate(true);
        println!("kshift-windows: window opened");
    });
}
