use serde::Serialize;

pub trait PowerBackend {
    fn acquire(&mut self) -> Result<u32, String>;
    fn release(&mut self, id: u32) -> Result<(), String>;
}

#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AwakeStatus {
    pub enabled: bool,
    pub expires_at: Option<u64>,
    pub duration_seconds: Option<u64>,
    pub error: Option<String>,
}

pub struct KeepAwake<B: PowerBackend> {
    backend: B,
    assertion: Option<u32>,
    expires_at: Option<u64>,
    duration_seconds: Option<u64>,
    error: Option<String>,
}

impl<B: PowerBackend> KeepAwake<B> {
    pub fn new(backend: B) -> Self {
        Self {
            backend,
            assertion: None,
            expires_at: None,
            duration_seconds: None,
            error: None,
        }
    }

    pub fn status(&self) -> AwakeStatus {
        AwakeStatus {
            enabled: self.assertion.is_some(),
            expires_at: self.expires_at,
            duration_seconds: self.duration_seconds,
            error: self.error.clone(),
        }
    }

    pub fn set(&mut self, enabled: bool, seconds: Option<u64>, now: u64) -> Result<(), String> {
        let result = self.apply(enabled, seconds, now);
        self.error = result.as_ref().err().cloned();
        result
    }

    fn apply(&mut self, enabled: bool, seconds: Option<u64>, now: u64) -> Result<(), String> {
        if !enabled {
            if let Some(id) = self.assertion {
                self.backend.release(id)?;
                self.assertion = None;
            }
            self.expires_at = None;
            return Ok(());
        }
        if !matches!(
            seconds,
            None | Some(300 | 1800 | 3600 | 7200 | 18000 | 28800)
        ) {
            return Err("请选择菜单中支持的亮屏时长".into());
        }
        let deadline = seconds
            .map(|value| {
                now.checked_add(value)
                    .ok_or_else(|| "结束时间超出范围".to_string())
            })
            .transpose()?;
        if self.assertion.is_none() {
            self.assertion = Some(self.backend.acquire()?);
        }
        self.expires_at = deadline;
        self.duration_seconds = seconds;
        Ok(())
    }

    pub fn tick(&mut self, now: u64) -> Result<(), String> {
        if self.expires_at.is_some_and(|deadline| now >= deadline) {
            self.set(false, None, now)?;
        }
        Ok(())
    }
}

impl<B: PowerBackend> Drop for KeepAwake<B> {
    fn drop(&mut self) {
        if let Some(id) = self.assertion {
            let _ = self.backend.release(id);
        }
    }
}

#[cfg(test)]
#[path = "keep_awake/tests.rs"]
mod tests;
