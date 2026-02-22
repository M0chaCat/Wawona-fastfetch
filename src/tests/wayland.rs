use crate::core::state::CompositorState;

#[test]
fn test_compositor_state_init() {
    let state = CompositorState::new(None);
    assert!(state.surfaces.is_empty());
    assert!(state.windows.is_empty());
    assert!(state.seat.keyboard.resources.is_empty());
    assert!(state.seat.pointer.resources.is_empty());
}

#[test]
fn test_seat_defaults() {
    let state = CompositorState::new(None);
    assert_eq!(state.seat.name, "seat0");
    assert!(state.seat.keyboard.focus.is_none());
    assert!(state.seat.pointer.focus.is_none());
}

#[test]
fn test_id_generation() {
    let mut state = CompositorState::new(None);
    let id1 = state.next_surface_id();
    let id2 = state.next_surface_id();
    assert_eq!(id1 + 1, id2);
}
