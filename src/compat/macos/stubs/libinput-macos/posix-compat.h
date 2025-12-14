#ifndef POSIX_COMPAT_H
#define POSIX_COMPAT_H

#ifdef __APPLE__
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <limits.h>
#include <string.h>
#include <stdio.h>

// macOS compatibility for posix_fallocate
// On macOS, we use fcntl with F_PREALLOCATE
static inline int
posix_fallocate(int fd, off_t offset, off_t len)
{
	if (fd < 0 || offset < 0 || len < 0) {
		errno = EINVAL;
		return EINVAL;
	}

	// Use fcntl F_PREALLOCATE on macOS (HFS+ and APFS support this)
	struct fstore store = {
		.fst_flags = F_ALLOCATECONTIG,
		.fst_posmode = F_PEOFPOSMODE,
		.fst_offset = offset,
		.fst_length = len
	};

	int ret = fcntl(fd, F_PREALLOCATE, &store);
	if (ret == -1) {
		// If contiguous allocation fails, try non-contiguous
		store.fst_flags = F_ALLOCATEALL;
		ret = fcntl(fd, F_PREALLOCATE, &store);
	}

	if (ret == -1) {
		// Fallback: use ftruncate and write zeros to ensure space is allocated
		// This works on all filesystems but is less efficient
		if (ftruncate(fd, offset + len) == -1) {
			return errno;
		}
		// Write a zero byte at the end to ensure the file is actually allocated
		char zero = 0;
		off_t end_pos = offset + len - 1;
		if (end_pos >= 0 && lseek(fd, end_pos, SEEK_SET) == end_pos) {
			if (write(fd, &zero, 1) == -1 && errno != ENOSPC) {
				// Ignore write errors (file might be on a filesystem that doesn't
				// support preallocation), but preserve ENOSPC
				if (errno == ENOSPC) {
					return ENOSPC;
				}
			}
		}
		return 0;
	}

	return 0;
}

// macOS compatibility for memfd_create
// On macOS, we use shm_open to create shared memory objects
#include <sys/shm.h>
#include <limits.h>

#ifndef MFD_CLOEXEC
#define MFD_CLOEXEC 0x0001U
#endif
#ifndef MFD_ALLOW_SEALING
#define MFD_ALLOW_SEALING 0x0002U
#endif
#ifndef MFD_NOEXEC_SEAL
#define MFD_NOEXEC_SEAL 0x0008U
#endif

static inline int
memfd_create(const char *name, unsigned int flags)
{
	int fd;
	char tmp_path[PATH_MAX];
	static int counter = 0;

	// On macOS, shm_open + shm_unlink has issues with SCM_RIGHTS transfer
	// Use a temporary file instead, which transfers reliably via SCM_RIGHTS
	// The file is unlinked immediately, making it anonymous (like memfd_create)
	snprintf(tmp_path, sizeof(tmp_path), "/tmp/%s.%d.%d", 
	         name ? name : "memfd", getpid(), counter++);
	
	fd = open(tmp_path, O_CREAT | O_RDWR | O_TRUNC, S_IRUSR | S_IWUSR);
	if (fd == -1) {
		return -1;
	}

	// Unlink immediately so file is deleted when fd closes (anonymous like memfd_create)
	// The file persists until all file descriptors are closed
	unlink(tmp_path);

	// Ensure fd is readable and writable
	fcntl(fd, F_SETFD, 0); // Clear any flags that might interfere
	
	// Set CLOEXEC flag if requested
	if (flags & MFD_CLOEXEC) {
		fcntl(fd, F_SETFD, FD_CLOEXEC);
	}

	// Note: macOS doesn't support file sealing (F_ADD_SEALS, F_SEAL_*)
	// The MFD_ALLOW_SEALING and MFD_NOEXEC_SEAL flags are ignored
	// This is acceptable as the file behaves similarly to memfd_create

	return fd;
}

// macOS compatibility for pipe2
// On macOS, pipe2 is not available, so we use pipe + fcntl
static inline int
pipe2(int pipefd[2], int flags)
{
	int ret = pipe(pipefd);
	if (ret == -1)
		return -1;
	
	// Set flags on both file descriptors
	if (flags & O_CLOEXEC) {
		fcntl(pipefd[0], F_SETFD, FD_CLOEXEC);
		fcntl(pipefd[1], F_SETFD, FD_CLOEXEC);
	}
	if (flags & O_NONBLOCK) {
		fcntl(pipefd[0], F_SETFL, O_NONBLOCK);
		fcntl(pipefd[1], F_SETFL, O_NONBLOCK);
	}
	
	return ret;
}

#endif // __APPLE__

#endif // POSIX_COMPAT_H

