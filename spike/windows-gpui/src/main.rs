//! Windows window spike for Kshift.
//!
//! Gate 1 proved that `gpui` builds for Windows. This gate proves that the
//! crate opens a window and enters its event loop on a Windows runner.
//!
//! The runner has no interactive desktop. A watchdog exits the process after
//! three seconds so the CI job can finish. The printed markers are the
//! evidence.

use std::thread;
use std::time::Duration;

use gpui::{
    div, px, size, App, Application, Bounds, Context, IntoElement, Render, Window, WindowBounds,
    WindowOptions,
};
use gpui::prelude::*;

struct Root;

impl Render for Root {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .flex()
            .flex_col()
            .size(px(900.0))
            .justify_center()
            .items_center()
            .bg(gpui::rgb(0x0B44A8))
            .text_xl()
            .text_color(gpui::white())
            .child("Kshift Windows Spike")
    }
}

fn main() {
    thread::spawn(|| {
        thread::sleep(Duration::from_secs(3));
        println!("kshift-windows-gpui-spike: window loop alive; exiting");
        std::process::exit(0);
    });

    Application::new().run(|cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(900.0), px(600.0)), cx);
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                ..Default::default()
            },
            |_, cx| cx.new(|_| Root),
        )
        .expect("open window");
        cx.activate(true);
        println!("kshift-windows-gpui-spike: window opened");
    });
}
