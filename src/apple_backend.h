#pragma once

// Compatibility header for macOS/iOS backend
// Provides alias for WWNCompositor

#include "WWNCompositor.h"

// Alias for backward compatibility
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
typedef WWNCompositor MacOSCompositor;
#else
typedef WWNCompositor MacOSCompositor;
#endif
