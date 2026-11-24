use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

#[derive(Default)]
pub struct RateLimiter {
    hits: Mutex<HashMap<String, Vec<Instant>>>,
}

impl RateLimiter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn allow(&self, key: &str, max: usize, window: Duration) -> bool {
        self.allow_at(key, max, window, Instant::now())
    }

    pub fn cooldown(&self, key: &str, period: Duration) -> bool {
        self.allow_at(key, 1, period, Instant::now())
    }

    fn allow_at(&self, key: &str, max: usize, window: Duration, now: Instant) -> bool {
        let mut hits = match self.hits.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        let entries = hits.entry(key.to_string()).or_default();
        entries.retain(|seen| now.duration_since(*seen) < window);
        if entries.len() >= max {
            return false;
        }
        entries.push(now);
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_after_limit_and_resets_after_window() {
        let limiter = RateLimiter::new();
        let window = Duration::from_secs(60);
        let start = Instant::now();
        assert!(limiter.allow_at("login:alice", 2, window, start));
        assert!(limiter.allow_at("login:alice", 2, window, start));
        assert!(!limiter.allow_at("login:alice", 2, window, start));
        assert!(limiter.allow_at("login:alice", 2, window, start + window));
    }

    #[test]
    fn separates_accounts_and_keys() {
        let limiter = RateLimiter::new();
        let window = Duration::from_secs(60);
        let start = Instant::now();
        assert!(limiter.allow_at("login:alice", 1, window, start));
        assert!(!limiter.allow_at("login:alice", 1, window, start));
        assert!(limiter.allow_at("login:bob", 1, window, start));
        assert!(limiter.allow_at("verify:alice", 1, window, start));
    }

    #[test]
    fn cooldown_holds_then_expires() {
        let limiter = RateLimiter::new();
        let period = Duration::from_secs(30);
        let start = Instant::now();
        assert!(limiter.allow_at("otp:alice", 1, period, start));
        assert!(!limiter.allow_at("otp:alice", 1, period, start));
        assert!(limiter.allow_at("otp:alice", 1, period, start + period));
    }
}
