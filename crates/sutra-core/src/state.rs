use crate::error::{Result, SutraError};
use crate::models::ThreadStatus;

pub struct StateMachine;

impl StateMachine {
    /// Validates and transitions from `current` to `target`.
    pub fn transition(current: ThreadStatus, target: ThreadStatus) -> Result<ThreadStatus> {
        if current == target {
            return Ok(current);
        }

        match (current, target) {
            // Waiting can be snoozed to Later or completed to Done
            (ThreadStatus::Waiting, ThreadStatus::Later) => Ok(ThreadStatus::Later),
            (ThreadStatus::Waiting, ThreadStatus::Done) => Ok(ThreadStatus::Done),

            // Later can be restored to Waiting or completed to Done
            (ThreadStatus::Later, ThreadStatus::Waiting) => Ok(ThreadStatus::Waiting),
            (ThreadStatus::Later, ThreadStatus::Done) => Ok(ThreadStatus::Done),

            // Done can be undone back to Waiting
            (ThreadStatus::Done, ThreadStatus::Waiting) => Ok(ThreadStatus::Waiting),

            // Self-transitions
            (ThreadStatus::Waiting, ThreadStatus::Waiting)
            | (ThreadStatus::Later, ThreadStatus::Later)
            | (ThreadStatus::Done, ThreadStatus::Done) => Ok(current),

            // Disallow direct Done -> Later without restoring first
            (ThreadStatus::Done, ThreadStatus::Later) => Err(SutraError::InvalidStateTransition {
                from: current.to_string(),
                to: target.to_string(),
            }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_transitions() {
        assert_eq!(
            StateMachine::transition(ThreadStatus::Waiting, ThreadStatus::Later).unwrap(),
            ThreadStatus::Later
        );
        assert_eq!(
            StateMachine::transition(ThreadStatus::Waiting, ThreadStatus::Done).unwrap(),
            ThreadStatus::Done
        );
        assert_eq!(
            StateMachine::transition(ThreadStatus::Later, ThreadStatus::Waiting).unwrap(),
            ThreadStatus::Waiting
        );
        assert_eq!(
            StateMachine::transition(ThreadStatus::Done, ThreadStatus::Waiting).unwrap(),
            ThreadStatus::Waiting
        );
    }

    #[test]
    fn test_noop_transition() {
        assert_eq!(
            StateMachine::transition(ThreadStatus::Waiting, ThreadStatus::Waiting).unwrap(),
            ThreadStatus::Waiting
        );
        assert_eq!(
            StateMachine::transition(ThreadStatus::Done, ThreadStatus::Done).unwrap(),
            ThreadStatus::Done
        );
    }

    #[test]
    fn test_invalid_transition() {
        let err = StateMachine::transition(ThreadStatus::Done, ThreadStatus::Later);
        assert!(err.is_err());
    }
}
