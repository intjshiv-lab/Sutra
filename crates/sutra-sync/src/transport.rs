use crate::peer::SyncDelta;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

pub const SUTRA_SYNC_PORT: u16 = 54321;

/// Start TCP listener on SUTRA_SYNC_PORT.
/// For each incoming connection: read a length-prefixed JSON SyncDelta,
/// pass to `on_delta` callback for CRDT merge.
///
/// ponytail: plain TCP — add XChaCha20 mutual TLS when QR pairing is built
pub async fn start_listener<F>(on_delta: F)
where
    F: Fn(SyncDelta) + Send + Sync + 'static,
{
    let listener = TcpListener::bind(format!("0.0.0.0:{SUTRA_SYNC_PORT}"))
        .await
        .expect("sutra-sync: failed to bind TCP listener");

    println!("[sutra-sync] Listening on port {SUTRA_SYNC_PORT}");

    let cb = std::sync::Arc::new(on_delta);

    loop {
        match listener.accept().await {
            Ok((socket, addr)) => {
                println!("[sutra-sync] Peer connected: {addr}");
                let cb = cb.clone();
                tokio::spawn(async move {
                    handle_connection(socket, cb).await;
                });
            }
            Err(e) => eprintln!("[sutra-sync] Accept error: {e}"),
        }
    }
}

async fn handle_connection<F>(mut socket: TcpStream, on_delta: std::sync::Arc<F>)
where
    F: Fn(SyncDelta) + Send + Sync,
{
    // Read 4-byte length prefix, then JSON payload
    let mut len_buf = [0u8; 4];
    if socket.read_exact(&mut len_buf).await.is_err() { return; }
    let len = u32::from_be_bytes(len_buf) as usize;

    let mut buf = vec![0u8; len];
    if socket.read_exact(&mut buf).await.is_err() { return; }

    if let Ok(delta) = serde_json::from_slice::<SyncDelta>(&buf) {
        on_delta(delta);
    }
}

/// Send a SyncDelta to a peer at the given address
pub async fn connect_to_peer(addr: std::net::SocketAddr, delta: &SyncDelta) -> std::io::Result<()> {
    let mut stream = TcpStream::connect(addr).await?;
    let payload = serde_json::to_vec(delta).map_err(|e| std::io::Error::other(e))?;
    let len = (payload.len() as u32).to_be_bytes();
    stream.write_all(&len).await?;
    stream.write_all(&payload).await?;
    Ok(())
}
