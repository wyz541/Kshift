//! Compile-only gate for the Windows UI spike.
//!
//! This binary proves one fact: the published `gpui` crate builds for
//! `x86_64-pc-windows-msvc`. It does not open a window yet. A window spike
//! follows after this gate passes.
//!
//! Run on the Windows CI runner only. The local checkout is macOS.

use gpui as _;

fn main() {
    println!("kshift-windows-gpui-spike: gpui dependency compiled");
}
