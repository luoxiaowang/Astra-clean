use super::*;

#[derive(Default)]
struct TestPower {
    active: bool,
    fail_acquire: bool,
    fail_release: bool,
}
impl PowerBackend for TestPower {
    fn acquire(&mut self) -> Result<u32, String> {
        if self.fail_acquire {
            return Err("创建失败".into());
        }
        assert!(!self.active, "重复创建会泄漏断言");
        self.active = true;
        Ok(42)
    }
    fn release(&mut self, id: u32) -> Result<(), String> {
        assert_eq!(id, 42);
        if self.fail_release {
            return Err("释放失败".into());
        }
        self.active = false;
        Ok(())
    }
}
#[test]
fn enable_failure_preserves_disabled_state() {
    let mut service = KeepAwake::new(TestPower {
        fail_acquire: true,
        ..Default::default()
    });
    assert!(service.set(true, Some(1800), 100).is_err());
    assert_eq!(service.assertion, None);
    assert_eq!(service.expires_at, None);
}
#[test]
fn expires_at_boundary_and_releases_power() {
    let mut service = KeepAwake::new(TestPower::default());
    service.set(true, Some(1800), 100).unwrap();
    service.tick(1899).unwrap();
    assert!(service.backend.active);
    service.tick(1900).unwrap();
    assert!(!service.backend.active);
    assert_eq!(service.assertion, None);
    assert_eq!(service.expires_at, None);
}
#[test]
fn updating_deadline_does_not_acquire_twice() {
    let mut service = KeepAwake::new(TestPower::default());
    service.set(true, Some(1800), 100).unwrap();
    service.set(true, Some(3600), 200).unwrap();
    assert_eq!(service.expires_at, Some(3800));
    service.tick(1900).unwrap();
    assert!(service.backend.active);
    service.set(true, None, 300).unwrap();
    service.tick(u64::MAX).unwrap();
    assert!(service.backend.active);
    service.set(false, None, 400).unwrap();
    assert!(!service.backend.active);
    service.set(false, None, 500).unwrap();
}
#[test]
fn release_failure_keeps_state_and_can_retry() {
    let mut service = KeepAwake::new(TestPower::default());
    service.set(true, Some(1800), 100).unwrap();
    service.backend.fail_release = true;
    assert!(service.tick(1900).is_err());
    assert_eq!(service.assertion, Some(42));
    service.backend.fail_release = false;
    service.tick(1901).unwrap();
    assert!(!service.backend.active);
}
#[test]
fn invalid_duration_does_not_change_existing_session() {
    let mut service = KeepAwake::new(TestPower::default());
    service.set(true, Some(1800), 100).unwrap();
    for duration in [0, 1, 1799, u64::MAX] {
        assert!(service.set(true, Some(duration), 200).is_err());
        assert_eq!(service.expires_at, Some(1900));
    }
}

#[test]
fn supports_all_menu_durations_and_expires_after_clock_jump() {
    for seconds in [300, 1800, 3600, 7200, 18000, 28800] {
        let mut service = KeepAwake::new(TestPower::default());
        service.set(true, Some(seconds), 100).unwrap();
        assert_eq!(service.expires_at, Some(100 + seconds));
        service.tick(100 + seconds - 1).unwrap();
        assert!(service.backend.active);
        service.tick(100 + seconds + 20).unwrap();
        assert!(!service.backend.active);
    }
}
