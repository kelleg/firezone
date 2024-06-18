use anyhow::{Context as _, Result};
use std::{os::unix::fs::PermissionsExt, path::Path};
use tokio::net::{UnixListener, UnixStream};

pub(crate) struct Server {
    listener: UnixListener,
}

/// Opaque wrapper around platform-specific IPC stream
pub(crate) type Stream = UnixStream;

impl Server {
    /// Platform-specific setup
    pub(crate) async fn new() -> Result<Self> {
        Self::new_with_path(&crate::platform::sock_path()).await
    }

    /// Uses a test path instead of what prod uses
    ///
    /// The test path doesn't need admin powers and won't conflict with the prod
    /// IPC service on a dev machine.
    #[cfg(test)]
    pub(crate) async fn new_for_test() -> Result<Self> {
        let dir = crate::known_dirs::runtime().context("Can't find runtime dir")?;
        // On a CI runner, the dir might not exist yet
        tokio::fs::create_dir_all(&dir).await?;
        let sock_path = dir.join("ipc_test.sock");
        Self::new_with_path(&sock_path).await
    }

    async fn new_with_path(sock_path: &Path) -> Result<Self> {
        // Remove the socket if a previous run left it there
        tokio::fs::remove_file(sock_path).await.ok();
        let listener = UnixListener::bind(sock_path)
            .with_context(|| format!("Couldn't bind UDS `{}`", sock_path.display()))?;
        let perms = std::fs::Permissions::from_mode(0o660);
        tokio::fs::set_permissions(sock_path, perms).await?;
        sd_notify::notify(true, &[sd_notify::NotifyState::Ready])?;
        Ok(Self { listener })
    }

    pub(crate) async fn next_client(&mut self) -> Result<Stream> {
        tracing::info!("Listening for GUI to connect over IPC...");
        let (stream, _) = self.listener.accept().await?;
        let cred = stream.peer_cred()?;
        tracing::info!(
            uid = cred.uid(),
            gid = cred.gid(),
            pid = cred.pid(),
            "Accepted an IPC connection"
        );
        Ok(stream)
    }
}