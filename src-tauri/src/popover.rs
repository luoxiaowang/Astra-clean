use objc2::{rc::Retained, MainThreadMarker};
use objc2_app_kit::{NSPopover, NSPopoverBehavior, NSViewController, NSWindow};
use objc2_foundation::{NSRectEdge, NSSize};
use std::cell::RefCell;
use tauri::{AppHandle, Manager};

// AppKit 对象只在主线程持有和访问，不跨线程传递裸指针。
thread_local! {
    static PANEL: RefCell<Option<Retained<NSPopover>>> = const { RefCell::new(None) };
}

pub fn setup(app: &AppHandle) -> Result<(), String> {
    let mtm = MainThreadMarker::new().ok_or("面板必须在主线程初始化")?;
    let host = app.get_webview_window("main").ok_or("缺少面板内容")?;
    let pointer = host.ns_window().map_err(|error| error.to_string())?;
    // Tauri 管理宿主 NSWindow 的生命周期，当前主线程内只借用该对象。
    let native_host = unsafe { &*pointer.cast::<NSWindow>() };
    let content = native_host.contentView().ok_or("缺少面板视图")?;
    let controller = NSViewController::new(mtm);
    content.removeFromSuperview();
    native_host.setContentView(None);
    controller.setView(&content);
    let popover = NSPopover::new(mtm);
    popover.setBehavior(NSPopoverBehavior::Transient);
    popover.setAnimates(false);
    popover.setContentViewController(Some(&controller));
    popover.setContentSize(NSSize::new(340.0, 492.0));
    PANEL.with(|state| *state.borrow_mut() = Some(popover));
    // 宿主只负责保留 Tauri IPC/WebView，从不作为独立窗口显示。
    host.hide().map_err(|error| error.to_string())
}

pub fn show(app: &AppHandle, toggle: bool) -> Result<(), String> {
    let tray = app.tray_by_id("main-tray").ok_or("菜单栏图标不可用")?;
    tray.with_inner_tray_icon(move |inner| {
        let Some(mtm) = MainThreadMarker::new() else {
            return;
        };
        let Some(item) = inner.ns_status_item() else {
            return;
        };
        let Some(button) = item.button(mtm) else {
            return;
        };
        PANEL.with(|state| {
            if let Some(popover) = state.borrow().as_ref() {
                if toggle && popover.isShown() {
                    popover.close();
                } else {
                    // 原生锚点自动处理 Retina、多屏坐标和屏幕边界。
                    popover.showRelativeToRect_ofView_preferredEdge(
                        button.bounds(),
                        &button,
                        NSRectEdge::MinY,
                    );
                }
            }
        });
    })
    .map_err(|error| error.to_string())
}

pub fn resize(app: &AppHandle, height: f64) -> Result<(), String> {
    app.run_on_main_thread(move || {
        PANEL.with(|state| {
            if let Some(popover) = state.borrow().as_ref() {
                popover.setContentSize(NSSize::new(340.0, height.clamp(200.0, 700.0)));
            }
        });
    })
    .map_err(|error| error.to_string())
}

pub fn hide(app: &AppHandle) -> Result<(), String> {
    app.run_on_main_thread(|| {
        PANEL.with(|state| {
            if let Some(popover) = state.borrow().as_ref() {
                popover.close();
            }
        });
    })
    .map_err(|error| error.to_string())
}
