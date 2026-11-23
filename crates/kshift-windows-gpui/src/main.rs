//! Kshift Windows client shell.
//!
//! The shell renders a read-only people schedule. Business data comes from
//! `kshift-ffi`; this file owns presentation only.

use std::time::Duration;

use chrono::NaiveDate;
use gpui::prelude::*;
use gpui::{
    div, px, rgb, size, App, Application, Bounds, Context, IntoElement, Render, SharedString,
    Window, WindowBounds, WindowOptions,
};
use kshift_windows::model::{self, Snapshot};
use kshift_windows::schedule::{self, PersonRow};

const NAME_WIDTH: f32 = 196.0;
const DAY_WIDTH: f32 = 116.0;
const BAR_HEIGHT: f32 = 30.0;
const LANE_STEP: f32 = 38.0;
const ROW_PADDING: f32 = 12.0;
const BAR_INSET: f32 = 8.0;
const MIN_ROW_HEIGHT: f32 = 72.0;
const DAY_COUNT: i64 = 7;

const BG: u32 = 0x0F_11_15;
const PANEL: u32 = 0x17_1A_21;
const HEADER: u32 = 0x1F_24_30;
const WEEKEND: u32 = 0x1A_1F_2A;
const BORDER: u32 = 0x2C_33_42;
const TEXT: u32 = 0xE6_E8_EE;
const MUTED: u32 = 0x9A_A1_B0;

struct ScheduleView {
    title: SharedString,
    subtitle: SharedString,
    days: Vec<NaiveDate>,
    rows: Vec<PersonRow>,
    tasks: Vec<model::Task>,
    error: Option<String>,
}

impl ScheduleView {
    fn from_snapshot(snapshot: Snapshot, anchor: NaiveDate) -> Self {
        let window_start = schedule::week_start(anchor);
        let days = schedule::week_days(window_start);
        let rows = schedule::build_rows(&snapshot, window_start, DAY_COUNT);
        let title: SharedString = snapshot.project.name.clone().into();
        let subtitle: SharedString = format!(
            "Revision {} · 只读 · 周 {} 至 {}",
            snapshot.project.current_revision,
            schedule::date_label(days[0]),
            schedule::date_label(days[6])
        )
        .into();
        Self {
            title,
            subtitle,
            days,
            rows,
            tasks: snapshot.tasks,
            error: None,
        }
    }

    fn error(message: String) -> Self {
        Self {
            title: "Kshift".into(),
            subtitle: "无法加载快照".into(),
            days: schedule::week_days(schedule::week_start(chrono::Local::now().date_naive())),
            rows: Vec::new(),
            tasks: Vec::new(),
            error: Some(message),
        }
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

    fn render_row(&self, row: &PersonRow) -> impl IntoElement {
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
}

impl Render for ScheduleView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let mut root = div()
            .flex()
            .flex_col()
            .size_full()
            .bg(rgb(BG))
            .p_6()
            .gap_4()
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
            list = list.child(self.render_row(row));
        }
        root.child(list)
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

fn parse_args() -> (Option<String>, Option<NaiveDate>) {
    let mut snapshot = None;
    let mut anchor = None;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--snapshot" => snapshot = args.next(),
            "--today" => anchor = args.next().and_then(|value| schedule::parse_date(&value)),
            other => snapshot = Some(other.to_owned()),
        }
    }
    (snapshot, anchor)
}

fn load_snapshot() -> Result<Snapshot, String> {
    let (path, _) = parse_args();
    if let Some(path) = path {
        return model::load(path);
    }
    if let Ok(path) = std::env::var("KSHIFT_SNAPSHOT") {
        return model::load(path);
    }
    if std::env::var("KSHIFT_ENDPOINT").is_ok() {
        return load_from_ffi();
    }
    Err("缺少数据源。使用 --snapshot <path>，或设置 KSHIFT_SNAPSHOT。".to_owned())
}

fn load_from_ffi() -> Result<Snapshot, String> {
    let endpoint = required_env("KSHIFT_ENDPOINT")?;
    let ca_path = required_env("KSHIFT_CA_PEM")?;
    let token = required_env("KSHIFT_TOKEN")?;
    let project_id = required_env("KSHIFT_PROJECT_ID")?;
    let ca = std::fs::read(&ca_path).map_err(|error| format!("read {ca_path}: {error}"))?;
    let client = kshift_ffi::host::HostClient::connect(
        &endpoint,
        ca,
        std::env::var("KSHIFT_TLS_DOMAIN").ok(),
        None,
    )?;
    client.set_token(&token)?;
    let json = client.snapshot_json(&project_id)?;
    model::parse(&json).map_err(|error| format!("parse ffi snapshot: {error}"))
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

    let (_, anchor) = parse_args();
    let anchor = anchor.unwrap_or_else(|| chrono::Local::now().date_naive());
    let view = match load_snapshot() {
        Ok(snapshot) => {
            println!(
                "kshift-windows: snapshot loaded project={} tasks={}",
                snapshot.project.name,
                snapshot.tasks.len()
            );
            ScheduleView::from_snapshot(snapshot, anchor)
        }
        Err(message) => {
            eprintln!("kshift-windows: {message}");
            ScheduleView::error(message)
        }
    };

    Application::new().run(move |cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(1180.0), px(760.0)), cx);
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                ..Default::default()
            },
            move |_, cx| cx.new(|_| view),
        )
        .expect("open window");
        cx.activate(true);
        println!("kshift-windows: window opened");
    });
}
