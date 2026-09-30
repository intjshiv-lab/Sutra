use serde::{Deserialize, Serialize};
use sutra_core::models::Thread;

/// A sync delta — sent between peers as a framed JSON payload
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncDelta {
    pub peer_id: String,
    pub threads: Vec<Thread>,
    pub timestamp: i64,
}

/// A discovered peer on the local network
#[derive(Debug, Clone)]
pub struct Peer {
    pub id: String,
    pub addr: std::net::SocketAddr,
    pub last_seen: i64,
}
