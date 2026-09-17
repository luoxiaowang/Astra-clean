use tauri::{
    image::Image,
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle,
};

// 用透明模板图标适配 macOS 明暗菜单栏，开启时填充中心。
pub fn tray_image(enabled: bool) -> Image<'static> {
    let size = 36u32;
    let mut pixels = vec![0u8; (size * size * 4) as usize];
    for y in 0..size {
        for x in 0..size {
            let dx = x as f64 - 17.5;
            let dy = y as f64 - 17.5;
            let r = (dx * dx + dy * dy).sqrt();
            let ring = (9.0..=12.0).contains(&r);
            let rays = (14.0..=17.0).contains(&r)
                && (dx.abs() < 1.2 || dy.abs() < 1.2 || (dx.abs() - dy.abs()).abs() < 1.5);
            if ring || rays || (enabled && r < 6.0) {
                pixels[((y * size + x) * 4 + 3) as usize] = 255;
            }
        }
    }
    Image::new_owned(pixels, size, size)
}

pub fn show_panel(app: &AppHandle) {
    if let Err(error) = crate::popover::show(app, false) {
        eprintln!("无法显示菜单栏面板：{error}");
    }
}

pub fn setup(app: &AppHandle) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "打开 OneSwitch", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "退出 OneSwitch", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &quit])?;
    TrayIconBuilder::with_id("main-tray")
        .icon(tray_image(false))
        .icon_as_template(true)
        .tooltip("OneSwitch · 常亮已关闭")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => show_panel(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                if let Err(error) = crate::popover::show(tray.app_handle(), true) {
                    eprintln!("无法显示菜单栏面板：{error}");
                }
            }
        })
        .build(app)?;
    Ok(())
}
