use wayland_server::backend::ClientId;

/// Trait for protocol state that needs to handle resource cleanup
pub trait ProtocolState {
    /// Called when a client disconnects
    fn client_disconnected(&mut self, client_id: ClientId);
}
