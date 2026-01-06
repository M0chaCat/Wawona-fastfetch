/**
 * logging.h
 * Wawona Unified Logging System
 *
 * Log format: YYYY-MM-DD HH:MM:SS [MODULE] emoji message
 *
 * Usage:
 *   LOG_INFO("COMPOSITOR", "✅ Server started on port %d", port);
 *   LOG_WARN("RENDERER", "⚠️ Fallback to software rendering");
 *   LOG_ERROR("KERNEL", "❌ Failed to spawn process: %s", err);
 *   LOG_DEBUG("INPUT", "🔍 Mouse moved to %d,%d", x, y);
 */

#pragma once

#include <stdio.h>
#include <stdarg.h>

// Log file handles
extern FILE *compositor_log_file;
extern FILE *client_log_file;

// Initialize logging
void init_compositor_logging(void);
void init_client_logging(void);

/**
 * Core logging function.
 *
 * @param module The module name (without brackets, e.g., "COMPOSITOR")
 * @param format Printf-style format string (should include emoji at start if desired)
 * @param ... Format arguments
 *
 * Output format: YYYY-MM-DD HH:MM:SS [MODULE] message
 */
void wawona_log(const char *module, const char *format, ...);

/**
 * Legacy logging function for compatibility.
 * @deprecated Use wawona_log() or LOG_* macros instead.
 *
 * Note: prefix should NOT include brackets - they are added automatically.
 */
void log_printf(const char *prefix, const char *format, ...);

// Flush all log buffers
void log_fflush(void);

// Cleanup logging
void cleanup_logging(void);

// Convenience macros for common log levels
// These all use the same format, emoji is part of the message

#define LOG_INFO(module, fmt, ...)  wawona_log(module, fmt, ##__VA_ARGS__)
#define LOG_WARN(module, fmt, ...)  wawona_log(module, fmt, ##__VA_ARGS__)
#define LOG_ERROR(module, fmt, ...) wawona_log(module, fmt, ##__VA_ARGS__)
#define LOG_DEBUG(module, fmt, ...) wawona_log(module, fmt, ##__VA_ARGS__)
