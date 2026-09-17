mod activity;
mod appearance;
mod desktop;
mod keep_awake;
mod popover;
mod power;

use keep_awake::{AwakeStatus, KeepAwake};
use power::MacPower;
use std::{
    sync::Mutex,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tauri::{Emitter, Manager, State};

type ActivityService = Mutex<activity::Activity<activity::MacActivity>>;

type AwakeService = Mutex<KeepAwake<MacPower>>;

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[tauri::command]
fn get_activity_status(
    service: State<ActivityService>,
) -> Result<activity::ActivityStatus, String> {
    Ok(service.lock().map_err(|_| "活跃状态锁不可用")?.status())
}

#[tauri::command]
fn set_activity(
    enabled: bool,
    service: State<ActivityService>,
) -> Result<activity::ActivityStatus, String> {
    let mut service = service.lock().map_err(|_| "活跃状态锁不可用")?;
    service.set(enabled)?;
    Ok(service.status())
}

#[tauri::command]
fn get_status(service: State<AwakeService>) -> Result<AwakeStatus, String> {
    let mut service = service.lock().map_err(|_| "状态锁不可用，请退出后重试")?;
    let _ = service.tick(now());
    Ok(service.status())
}

#[tauri::command]
fn set_awake(
    enabled: bool,
    duration_seconds: Option<u64>,
    service: State<AwakeService>,
    app: tauri::AppHandle,
) -> Result<AwakeStatus, String> {
    let mut service = service.lock().map_err(|_| "状态锁不可用，请退出后重试")?;
    let result = service.set(enabled, duration_seconds, now());
    let status = service.status();
    drop(service);
    publish(&app, &status);
    result.map(|_| status)
}

#[tauri::command]
fn resize_panel(height: f64, app: tauri::AppHandle) -> Result<(), String> {
    if !height.is_finite() {
        return Err("面板尺寸无效".into());
    }
    popover::resize(&app, height)
}

#[tauri::command]
fn hide_panel(app: tauri::AppHandle) -> Result<(), String> {
    popover::hide(&app)
}

#[tauri::command]
fn quit_app(app: tauri::AppHandle) {
    app.exit(0);
}

fn publish(app: &tauri::AppHandle, status: &AwakeStatus) {
    let _ = app.emit("awake-status", status);
    let active = app
        .state::<ActivityService>()
        .lock()
        .map(|service| service.status().enabled)
        .unwrap_or(false);
    if let Some(tray) = app.tray_by_id("main-tray") {
        let _ = tray
            .set_icon_with_as_template(Some(desktop::tray_image(status.enabled || active)), true);
        let _ = tray.set_tooltip(Some(if active {
            "OneSwitch · 保持活跃中"
        } else if status.enabled {
            "OneSwitch · 常亮已开启"
        } else {
            "OneSwitch · 常亮已关闭"
        }));
    }
}

fn start_timer(app: tauri::AppHandle) {
    std::thread::spawn(move || {
        let mut previous = None;
        let mut previous_active = false;
        loop {
            std::thread::sleep(Duration::from_secs(1));
            let active = if let Ok(mut activity) = app.state::<ActivityService>().lock() {
                activity.tick();
                activity.status().enabled
            } else {
                false
            };
            if let Ok(mut service) = app.state::<AwakeService>().lock() {
                let _ = service.tick(now());
                let status = service.status();
                drop(service);
                if previous.as_ref() != Some(&status) || active != previous_active {
                    publish(&app, &status);
                    previous = Some(status);
                    previous_active = active;
                }
            }
        }
    });
}

pub fn run() {
    let app = tauri::Builder::default()
        .enable_macos_default_menu(false)
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            desktop::show_panel(app)
        }))
        .plugin(
            tauri_plugin_autostart::Builder::new()
                .macos_launcher(tauri_plugin_autostart::MacosLauncher::LaunchAgent)
                .args(["--autostart"])
                .build(),
        )
        .manage(Mutex::new(KeepAwake::new(MacPower)))
        .manage(Mutex::new(activity::Activity::new(
            activity::MacActivity::new(),
        )))
        .invoke_handler(tauri::generate_handler![
            get_status,
            get_activity_status,
            set_activity,
            activity::request_activity_permission,
            set_awake,
            hide_panel,
            quit_app,
            resize_panel,
            appearance::set_dark_mode
        ])
        .setup(|app| {
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            desktop::setup(app.handle())?;
            popover::setup(app.handle()).map_err(std::io::Error::other)?;
            start_timer(app.handle().clone());
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .build(tauri::generate_context!())
        .expect("OneSwitch 启动失败");
    app.run(|app, event| {
        if matches!(event, tauri::RunEvent::Reopen { .. }) {
            desktop::show_panel(app);
        }
        if matches!(
            event,
            tauri::RunEvent::ExitRequested { .. } | tauri::RunEvent::Exit
        ) {
            if let Ok(mut activity) = app.state::<ActivityService>().lock() {
                let _ = activity.set(false);
            }
            if let Ok(mut service) = app.state::<AwakeService>().lock() {
                let _ = service.set(false, None, now());
            }
        }
    });
}
