#![allow(unused_imports)]
use nix::sys::socket as real_socket;
pub use real_socket::*;
use std::os::unix::io::{AsRawFd, RawFd, OwnedFd};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SockFlag(u32);

impl SockFlag {
    pub const SOCK_CLOEXEC: Self = Self(1 << 0);
    pub const SOCK_NONBLOCK: Self = Self(1 << 1);
    pub fn empty() -> Self { Self(0) }
    pub fn contains(&self, other: Self) -> bool { (self.0 & other.0) != 0 }
}

impl std::ops::BitOr for SockFlag {
    type Output = Self;
    fn bitor(self, rhs: Self) -> Self { Self(self.0 | rhs.0) }
}

pub fn socket<P>(domain: real_socket::AddressFamily, ty: real_socket::SockType, flags: SockFlag, protocol: P) -> nix::Result<OwnedFd> 
where P: Into<Option<real_socket::SockProtocol>> {
    let fd = real_socket::socket(domain, ty, real_socket::SockFlag::empty(), protocol)?;
    if flags.contains(SockFlag::SOCK_CLOEXEC) {
let _ = nix::fcntl::fcntl(&fd, nix::fcntl::F_SETFD(nix::fcntl::FdFlag::FD_CLOEXEC));
    }
    if flags.contains(SockFlag::SOCK_NONBLOCK) {
let _ = nix::fcntl::fcntl(&fd, nix::fcntl::F_SETFL(nix::fcntl::OFlag::O_NONBLOCK));
    }
    Ok(fd)
}

pub fn socketpair<P>(domain: real_socket::AddressFamily, ty: real_socket::SockType, protocol: P, flags: SockFlag) -> nix::Result<(OwnedFd, OwnedFd)> 
where P: Into<Option<real_socket::SockProtocol>> {
    let (fd1, fd2) = real_socket::socketpair(domain, ty, protocol, real_socket::SockFlag::empty())?;
    if flags.contains(SockFlag::SOCK_CLOEXEC) {
let _ = nix::fcntl::fcntl(&fd1, nix::fcntl::F_SETFD(nix::fcntl::FdFlag::FD_CLOEXEC));
let _ = nix::fcntl::fcntl(&fd2, nix::fcntl::F_SETFD(nix::fcntl::FdFlag::FD_CLOEXEC));
    }
    if flags.contains(SockFlag::SOCK_NONBLOCK) {
let _ = nix::fcntl::fcntl(&fd1, nix::fcntl::F_SETFL(nix::fcntl::OFlag::O_NONBLOCK));
let _ = nix::fcntl::fcntl(&fd2, nix::fcntl::F_SETFL(nix::fcntl::OFlag::O_NONBLOCK));
    }
    Ok((fd1, fd2))
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn pipe2(flags: nix::fcntl::OFlag) -> nix::Result<(OwnedFd, OwnedFd)> {
    use nix::fcntl;
    use nix::unistd;
    let (r, w) = unistd::pipe()?;
    let _ = fcntl::fcntl(&r, fcntl::F_SETFL(flags));
    let _ = fcntl::fcntl(&w, fcntl::F_SETFL(flags));
    Ok((r, w))
}

#[derive(Debug, Copy, Clone)]
pub enum Id {
    All,
    Pid(nix::unistd::Pid),
    Pgid(nix::unistd::Pid),
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn waitid(_id: Id, _flags: nix::sys::wait::WaitPidFlag) -> nix::Result<nix::sys::wait::WaitStatus> {
    nix::sys::wait::waitpid(None, Some(nix::sys::wait::WaitPidFlag::WNOHANG))
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn ppoll(fds: &mut [nix::poll::PollFd], timeout: Option<nix::sys::time::TimeSpec>, _sigmask: Option<nix::sys::signal::SigSet>) -> nix::Result<nix::libc::c_int> {
    let timeout_ms = match timeout {
Some(ts) => (ts.tv_sec() * 1000 + ts.tv_nsec() / 1_000_000) as nix::libc::c_int,
None => -1,
    };
    
    // Use libc::poll directly to avoid PollTimeout type issues in newer nix versions
    let res = unsafe {
nix::libc::poll(
    fds.as_mut_ptr() as *mut nix::libc::pollfd,
    fds.len() as nix::libc::nfds_t,
    timeout_ms
)
    };
    
    if res < 0 {
Err(nix::errno::Errno::last())
    } else {
Ok(res)
    }
}

pub mod memfd {
    use std::os::unix::io::OwnedFd;
    use nix::Result;
    
    #[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
    #[allow(dead_code)]
    pub struct MemFdCreateFlag(u32);
    impl MemFdCreateFlag {
pub const MFD_CLOEXEC: Self = Self(0x0001);
pub const MFD_ALLOW_SEALING: Self = Self(0x0002);
#[allow(dead_code)]
pub fn empty() -> Self { Self(0) }
pub fn contains(&self, other: Self) -> bool { (self.0 & other.0) != 0 }
    }
    impl std::ops::BitOr for MemFdCreateFlag {
type Output = Self;
fn bitor(self, rhs: Self) -> Self { Self(self.0 | rhs.0) }
    }
    
    pub type MFdFlags = MemFdCreateFlag;

    pub fn memfd_create(name: &std::ffi::CStr, _flags: MemFdCreateFlag) -> Result<OwnedFd> {
use nix::errno::Errno;
use nix::fcntl::OFlag;
use nix::sys::mman;
use nix::sys::stat::Mode;
use nix::unistd;

// Try shm_open-backed emulation first.
// On iOS this can be denied by sandbox policy, so fall back to
// an unlinked regular file in a writable runtime/temp directory.
let name_bytes = name.to_bytes();
let shm_name = if name_bytes.starts_with(b"/") {
    std::borrow::Cow::Borrowed(name)
} else {
    let mut bytes = Vec::with_capacity(name_bytes.len() + 2);
    bytes.push(b'/');
    bytes.extend_from_slice(name_bytes);
    bytes.push(0);
    std::borrow::Cow::Owned(unsafe { std::ffi::CStr::from_bytes_with_nul_unchecked(&bytes).to_owned() })
};

match mman::shm_open(
    shm_name.as_ref(),
    OFlag::O_RDWR | OFlag::O_CREAT | OFlag::O_EXCL,
    Mode::S_IRUSR | Mode::S_IWUSR,
) {
    Ok(fd) => {
        // Unlink immediately so it disappears when closed.
        let _ = mman::shm_unlink(shm_name.as_ref());
        return Ok(fd);
    }
    Err(Errno::EPERM) | Err(Errno::EACCES) | Err(Errno::ENOSYS) => {
        // Continue to fallback below.
    }
    Err(e) => return Err(e),
}

let runtime_dir = std::env::var("XDG_RUNTIME_DIR")
    .ok()
    .filter(|v| !v.is_empty())
    .unwrap_or_else(|| std::env::temp_dir().to_string_lossy().into_owned());
let base_name = if name_bytes.is_empty() {
    "waypipe-memfd"
} else {
    std::str::from_utf8(name_bytes).unwrap_or("waypipe-memfd")
};

// Try multiple unique names to avoid collisions.
for attempt in 0..32u32 {
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let path = format!(
        "{}/{}.{}.{}.tmp",
        runtime_dir,
        base_name,
        std::process::id(),
        nonce.wrapping_add(attempt as u128)
    );
    match nix::fcntl::open(
        path.as_str(),
        OFlag::O_RDWR | OFlag::O_CREAT | OFlag::O_EXCL | OFlag::O_CLOEXEC,
        Mode::S_IRUSR | Mode::S_IWUSR,
    ) {
        Ok(fd) => {
            let _ = unistd::unlink(path.as_str());
            return Ok(fd);
        }
        Err(Errno::EEXIST) => continue,
        Err(e) => return Err(e),
    }
}

Err(Errno::EEXIST)
    }
}
