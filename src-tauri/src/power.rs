use crate::keep_awake::PowerBackend;
use core_foundation::{
    base::TCFType,
    string::{CFString, CFStringRef},
};

#[link(name = "IOKit", kind = "framework")]
unsafe extern "C" {
    fn IOPMAssertionCreateWithName(
        kind: CFStringRef,
        level: u32,
        name: CFStringRef,
        id: *mut u32,
    ) -> i32;
    fn IOPMAssertionRelease(id: u32) -> i32;
}

pub struct MacPower;

impl PowerBackend for MacPower {
    fn acquire(&mut self) -> Result<u32, String> {
        let kind = CFString::new("PreventUserIdleDisplaySleep");
        let reason = CFString::new("OneSwitch Display Awake");
        let mut id = 0;
        // CFString 在调用期间存活，id 指向有效的 u32；由系统返回断言所有权。
        let result = unsafe {
            IOPMAssertionCreateWithName(
                kind.as_concrete_TypeRef(),
                255,
                reason.as_concrete_TypeRef(),
                &mut id,
            )
        };
        if result != 0 {
            return Err(format!("无法开启常亮，系统错误：{result:#x}"));
        }
        Ok(id)
    }

    fn release(&mut self, id: u32) -> Result<(), String> {
        // 只释放当前服务成功取得且尚未释放的断言。
        let result = unsafe { IOPMAssertionRelease(id) };
        if result != 0 {
            return Err(format!("无法关闭常亮，请重试，系统错误：{result:#x}"));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::keep_awake::KeepAwake;
    use std::process::Command;

    #[test]
    #[ignore = "短暂创建真实电源断言；需在 macOS 上显式执行"]
    fn native_assertion_is_visible_and_released() {
        let mut service = KeepAwake::new(MacPower);
        service.set(true, None, 0).unwrap();
        let pid_marker = format!("pid {}(", std::process::id());
        let assertions = || {
            let output = Command::new("pmset")
                .args(["-g", "assertions"])
                .output()
                .unwrap();
            assert!(output.status.success());
            String::from_utf8_lossy(&output.stdout).into_owned()
        };
        let is_ours = |line: &str| line.contains(&pid_marker) && line.contains("OneSwitch");
        let current = assertions();
        assert!(
            current.lines().any(is_ours),
            "pid marker={pid_marker}\n{current}"
        );
        service.set(false, None, 0).unwrap();
        assert!(!assertions().lines().any(is_ours));
    }
}
