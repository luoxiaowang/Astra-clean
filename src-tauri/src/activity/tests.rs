use super::*;
#[derive(Default)]
struct Fake {
    allowed: bool,
    idle: f64,
    held: bool,
    pulses: usize,
    running: bool,
}
impl Backend for Fake {
    fn allowed(&self) -> bool {
        self.allowed
    }
    fn idle(&self) -> f64 {
        self.idle
    }
    fn held(&self) -> bool {
        self.held
    }
    fn start(&mut self) -> Result<(), String> {
        self.running = true;
        Ok(())
    }
    fn stop(&mut self) -> Result<(), String> {
        self.running = false;
        Ok(())
    }
    fn pulse(&mut self) -> Result<(), String> {
        self.pulses += 1;
        Ok(())
    }
}
fn service() -> Activity<Fake> {
    Activity::new(Fake {
        allowed: true,
        ..Fake::default()
    })
}
#[test]
fn missing_permission_never_starts() {
    let mut s = Activity::new(Fake::default());
    assert!(s.set(true).is_err());
    assert!(!s.status().enabled);
    assert!(!s.backend.running);
}
#[test]
fn idle_only_and_no_drag_interruption() {
    let mut s = service();
    s.set(true).unwrap();
    s.tick();
    assert_eq!(s.backend.pulses, 0);
    s.backend.idle = 45.;
    s.backend.held = true;
    s.tick();
    assert_eq!(s.backend.pulses, 0);
    s.backend.held = false;
    s.tick();
    assert_eq!(s.backend.pulses, 1);
    s.backend.idle = 1.;
    s.tick();
    assert_eq!(s.backend.pulses, 1);
    assert!(s.enabled);
    s.backend.idle = 45.;
    s.tick();
    assert_eq!(s.backend.pulses, 2);
    s.set(false).unwrap();
    s.tick();
    assert_eq!(s.backend.pulses, 2);
    assert!(!s.backend.running);
}
#[test]
fn ineffective_event_stops_and_reports_error() {
    let mut s = service();
    s.set(true).unwrap();
    s.backend.idle = 45.;
    s.tick();
    s.tick();
    assert!(!s.enabled);
    assert!(!s.backend.running);
    assert!(s.error.is_some());
}
#[test]
fn revoked_permission_stops_background_work() {
    let mut s = service();
    s.set(true).unwrap();
    s.backend.allowed = false;
    s.tick();
    assert!(!s.enabled);
    assert!(!s.backend.running);
    assert!(s.error.is_some());
}
#[test]
fn disable_cancels_pending_verification() {
    let mut s = service();
    s.set(true).unwrap();
    s.backend.idle = 45.;
    s.tick();
    s.set(false).unwrap();
    s.tick();
    assert!(s.error.is_none());
}
