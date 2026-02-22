
use wayland_server::Resource;


#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShmBufferData {
    pub width: i32,
    pub height: i32,
    pub stride: i32,
    pub format: u32,
    pub offset: i32,
    pub pool_id: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DmaBufData {
    pub width: u32,
    pub height: u32,
    pub format: u32,
    pub modifier: u64,
    pub fds: Vec<i32>,
    pub offsets: Vec<u32>,
    pub strides: Vec<u32>,
}

/// Represents a GPU-ready or CPU-accessible buffer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BufferType {
    Shm(ShmBufferData),
    DmaBuf(DmaBufData),
    Native(NativeBufferData), // e.g. MacOS IOSurface
    None,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NativeBufferData {
    pub id: u64,
    pub width: i32,
    pub height: i32,
    pub format: u32,
}

#[derive(Debug, Clone)]
pub struct Buffer {
    pub id: u32,
    pub buffer_type: BufferType,
    pub released: bool,
    pub resource: Option<wayland_server::protocol::wl_buffer::WlBuffer>,
}

impl Buffer {
    pub fn new(id: u32, buffer_type: BufferType, resource: Option<wayland_server::protocol::wl_buffer::WlBuffer>) -> Self {
        Self {
            id,
            buffer_type,
            released: false,
            resource,
        }
    }

    /// Notify the client that the buffer is no longer being used
    pub fn release(&mut self) {
        if self.released {
            return;
        }
        
        if let Some(resource) = &self.resource {
            if resource.is_alive() {
                resource.release();
            }
        }
        
        self.released = true;
    }
}

impl BufferType {
    pub fn dimensions(&self) -> Option<(i32, i32)> {
        match self {
            BufferType::Shm(data) => Some((data.width, data.height)),
            BufferType::DmaBuf(data) => Some((data.width as i32, data.height as i32)),
            BufferType::Native(data) => Some((data.width, data.height)),
            BufferType::None => None,
        }
    }
}

impl Default for BufferType {
    fn default() -> Self {
        Self::None
    }
}
