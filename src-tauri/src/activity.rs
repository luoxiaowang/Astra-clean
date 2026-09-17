use crate::{keep_awake::KeepAwake, power::MacPower};
use serde::Serialize;
use std::{ffi::c_void, ptr};

const PERMISSION_ERROR: &str =
    "请在系统设置 → 隐私与安全性 → 辅助功能中允许 OneSwitch，然后重新开启保持活跃";

pub trait Backend {
    fn allowed(&self) -> bool;
    fn idle(&self) -> f64;
    fn held(&self) -> bool;
    fn start(&mut self) -> Result<(), String>;
    fn stop(&mut self) -> Result<(), String>;
    fn pulse(&mut self) -> Result<(), String>;
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivityStatus {
    pub enabled: bool,
    permission_granted: bool,
    error: Option<String>,
}

pub struct Activity<B: Backend> {
    backend: B,
    enabled: bool,
    pending: bool,
    error: Option<String>,
}
impl<B: Backend> Activity<B> {
    pub fn new(backend: B) -> Self {
        Self {
            backend,
            enabled: false,
            pending: false,
            error: None,
        }
    }
    pub fn status(&self) -> ActivityStatus {
        ActivityStatus {
            enabled: self.enabled,
            permission_granted: self.backend.allowed(),
            error: self.error.clone(),
        }
    }
    pub fn set(&mut self, enabled: bool) -> Result<(), String> {
        let result = if enabled {
            if !self.backend.allowed() {
                Err(PERMISSION_ERROR.into())
            } else {
                self.backend.start().map(|()| {
                    self.enabled = true;
                })
            }
        } else {
            // 即使断言释放失败，也立即停止发送输入事件；后续 tick 重试清理。
            self.enabled = false;
            self.pending = false;
            self.backend.stop()
        };
        self.error = result.as_ref().err().cloned();
        result
    }
    pub fn tick(&mut self) {
        if !self.enabled {
            let _ = self.backend.stop();
            return;
        }
        let result = self.step();
        if let Err(error) = result {
            self.enabled = false;
            self.pending = false;
            let cleanup = self.backend.stop().err();
            self.error = Some(match cleanup {
                Some(message) => format!("{error}；{message}"),
                None => error,
            });
        }
    }
    fn step(&mut self) -> Result<(), String> {
        if !self.backend.allowed() {
            return Err(PERMISSION_ERROR.into());
        }
        let idle = self.backend.idle();
        if !idle.is_finite() || idle < 0. {
            return Err("无法读取系统闲置状态".into());
        }
        // CGEventPost 没有返回值，下一次 tick 验证计时确实已重置。
        if self.pending {
            self.pending = false;
            if idle >= 45. {
                return Err(
                    "活动事件未重置系统闲置计时，已停止保持活跃。请检查辅助功能权限后重试".into(),
                );
            }
        }
        if idle >= 45. && !self.backend.held() {
            self.backend.pulse()?;
            self.pending = true;
        }
        Ok(())
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
struct Point {
    x: f64,
    y: f64,
}
#[link(name = "CoreGraphics", kind = "framework")]
unsafe extern "C" {
    fn CGPreflightPostEventAccess() -> bool;
    fn CGRequestPostEventAccess() -> bool;
    fn CGEventSourceSecondsSinceLastEventType(state: i32, event_type: u32) -> f64;
    fn CGEventSourceButtonState(state: i32, button: u32) -> bool;
    fn CGEventSourceFlagsState(state: i32) -> u64;
    fn CGEventCreate(source: *const c_void) -> *const c_void;
    fn CGEventGetLocation(event: *const c_void) -> Point;
    fn CGEventSetType(event: *const c_void, event_type: u32);
    fn CGEventSetLocation(event: *const c_void, location: Point);
    fn CGEventSetFlags(event: *const c_void, flags: u64);
    fn CGEventPost(tap: u32, event: *const c_void);
}
#[link(name = "CoreFoundation", kind = "framework")]
unsafe extern "C" {
    fn CFRelease(value: *const c_void);
}

pub struct MacActivity {
    awake: KeepAwake<MacPower>,
}
impl MacActivity {
    pub fn new() -> Self {
        Self {
            awake: KeepAwake::new(MacPower),
        }
    }
}
impl Backend for MacActivity {
    fn allowed(&self) -> bool {
        unsafe { CGPreflightPostEventAccess() }
    }
    fn idle(&self) -> f64 {
        unsafe { CGEventSourceSecondsSinceLastEventType(0, u32::MAX) }
    }
    fn held(&self) -> bool {
        // 按住任意常见鼠标键或修饰键时不产生事件，以免干扰拖拽和快捷操作。
        unsafe {
            (0..32).any(|button| CGEventSourceButtonState(0, button))
                || CGEventSourceFlagsState(0) & 0x00fe0000 != 0
        }
    }
    fn start(&mut self) -> Result<(), String> {
        self.awake.set(true, None, 0)
    }
    fn stop(&mut self) -> Result<(), String> {
        self.awake.set(false, None, 0)
    }
    fn pulse(&mut self) -> Result<(), String> {
        // 在同一次调用中读取位置并发送同位置 mouseMoved；不点击、不键入、不主动位移。
        unsafe {
            let event = CGEventCreate(ptr::null());
            if event.is_null() {
                return Err("无法创建系统活动事件".into());
            }
            let location = CGEventGetLocation(event);
            CGEventSetType(event, 5); // kCGEventMouseMoved
            CGEventSetLocation(event, location);
            CGEventSetFlags(event, CGEventSourceFlagsState(0));
            CGEventPost(0, event); // kCGHIDEventTap
            CFRelease(event);
        }
        Ok(())
    }
}

#[tauri::command]
pub fn request_activity_permission() -> bool {
    // 仅用户点击授权按钮时触发系统授权界面，后台检测不弹窗。
    unsafe { CGRequestPostEventAccess() }
}

#[cfg(test)]
#[path = "activity/tests.rs"]
mod tests;
