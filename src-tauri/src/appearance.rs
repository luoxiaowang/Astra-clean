use std::{
    process::{Command, Output, Stdio},
    sync::Mutex,
    time::{Duration, Instant},
};

static APPEARANCE_LOCK: Mutex<()> = Mutex::new(());

fn parse_result(output: Output) -> Result<bool, String> {
    if !output.status.success() {
        let error = String::from_utf8_lossy(&output.stderr);
        if error.contains("-1743") || error.contains("-10004") {
            return Err(
                "请在系统设置 → 隐私与安全性 → 自动化中，允许 OneSwitch 控制“系统事件”，然后重试。"
                    .into(),
            );
        }
        return Err(format!("系统外观切换失败：{}", error.trim()));
    }
    match String::from_utf8_lossy(&output.stdout).trim() {
        "true" => Ok(true),
        "false" => Ok(false),
        _ => Err("无法确认系统外观，请重试。".into()),
    }
}

fn apply_system_appearance(enabled: bool) -> Result<bool, String> {
    let _guard = APPEARANCE_LOCK
        .try_lock()
        .map_err(|_| "正在切换系统外观，请稍候。")?;
    // 只接受布尔值，不拼接用户提供的脚本文本；修改系统外观而非应用局部主题。
    let script = format!("tell application \"System Events\"\ntell appearance preferences\nset dark mode to {enabled}\nreturn dark mode\nend tell\nend tell");
    let mut child = Command::new("/usr/bin/osascript")
        .args(["-e", &script])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("无法启动系统外观服务：{error}"))?;
    let start = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if start.elapsed() < Duration::from_secs(45) => {
                std::thread::sleep(Duration::from_millis(100))
            }
            result => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(match result {
                    Err(error) => format!("系统外观服务异常：{error}"),
                    _ => "切换超时。如有系统授权提示，请允许后重试。".into(),
                });
            }
        }
    }
    parse_result(
        child
            .wait_with_output()
            .map_err(|error| format!("读取系统外观失败：{error}"))?,
    )
}

#[tauri::command]
pub async fn set_dark_mode(enabled: bool) -> Result<bool, String> {
    // 授权对话框可能等待用户操作，不占用 UI 主线程。
    tauri::async_runtime::spawn_blocking(move || apply_system_appearance(enabled))
        .await
        .map_err(|error| format!("系统外观任务失败：{error}"))?
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::process::ExitStatusExt;

    fn output(code: i32, text: &str, error: &str) -> Output {
        Output {
            status: std::process::ExitStatus::from_raw(code << 8),
            stdout: text.as_bytes().to_vec(),
            stderr: error.as_bytes().to_vec(),
        }
    }
    #[test]
    fn returns_confirmed_system_state() {
        assert!(parse_result(output(0, "true\n", "")).unwrap());
        assert!(!parse_result(output(0, "false\n", "")).unwrap());
    }
    #[test]
    fn rejects_unknown_response() {
        assert!(parse_result(output(0, "", "")).is_err());
    }
    #[test]
    fn permission_denial_provides_actionable_instructions() {
        let result = parse_result(output(1, "", "Not authorized (-1743)"));
        assert!(result.unwrap_err().contains("自动化"));
    }
}
