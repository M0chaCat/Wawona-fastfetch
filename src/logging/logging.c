/**
 * logging.c
 * Wawona Unified Logging System
 *
 * Output format: YYYY-MM-DD HH:MM:SS [MODULE] message
 */

#include "logging.h"
#include <errno.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

static pthread_mutex_t log_mutex = PTHREAD_MUTEX_INITIALIZER;

#ifdef __ANDROID__
#include <android/log.h>
#endif

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

FILE *compositor_log_file = NULL;
FILE *client_log_file = NULL;

void init_compositor_logging(void) {
  // Ensure logs directory exists
  struct stat st = {0};
  if (stat("logs", &st) == -1) {
    if (mkdir("logs", 0755) == -1 && errno != EEXIST) {
      // Silently fail - logging to file is optional
    }
  }

  compositor_log_file = fopen("logs/wawona_compositor.log", "w");
  // Silently fail if can't open - stdout logging still works
}

void init_client_logging(void) {
  struct stat st = {0};
  if (stat("logs", &st) == -1) {
    if (mkdir("logs", 0755) == -1 && errno != EEXIST) {
      // Silently fail
    }
  }

  client_log_file = fopen("logs/wawona_client.log", "w");
}

/**
 * Core logging function with unified format.
 */
void wawona_log(const char *module, const char *format, ...) {
  va_list args;
  time_t now;
  char time_str[64];
  struct tm *tm_info;

  // Get current time
  time(&now);
  tm_info = localtime(&now);
  strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", tm_info);

  // Print to stdout: YYYY-MM-DD HH:MM:SS [MODULE] message
  pthread_mutex_lock(&log_mutex);
  printf("%s [%s] ", time_str, module);
  va_start(args, format);
  vprintf(format, args);
  va_end(args);

  // Ensure newline (but don't double it if format already has one)
  size_t len = strlen(format);
  if (len == 0 || format[len - 1] != '\n') {
    printf("\n");
  }
  fflush(stdout);

#ifdef __ANDROID__
  // Print to Android logcat
  va_start(args, format);
  int priority = ANDROID_LOG_INFO;
  if (strstr(format, "❌") || strstr(format, "ERROR"))
    priority = ANDROID_LOG_ERROR;
  else if (strstr(format, "⚠️") || strstr(format, "WARN"))
    priority = ANDROID_LOG_WARN;
  else if (strstr(format, "🔍") || strstr(format, "DEBUG"))
    priority = ANDROID_LOG_DEBUG;

  __android_log_vprint(priority, module, format, args);
  va_end(args);
#endif

  // Print to log file if open
  if (compositor_log_file) {
    fprintf(compositor_log_file, "%s [%s] ", time_str, module);
    va_start(args, format);
    vfprintf(compositor_log_file, format, args);
    va_end(args);
    if (len == 0 || format[len - 1] != '\n') {
      fprintf(compositor_log_file, "\n");
    }
    fflush(compositor_log_file);
  }
  pthread_mutex_unlock(&log_mutex);
}

/**
 * Legacy logging function for compatibility.
 * Strips brackets from prefix if present.
 */
void log_printf(const char *prefix, const char *format, ...) {
  va_list args;
  time_t now;
  char time_str[64];
  struct tm *tm_info;

  // Get current time
  time(&now);
  tm_info = localtime(&now);
  strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", tm_info);

  // Clean up the prefix - remove brackets and extra spaces
  char clean_prefix[64] = {0};
  const char *src = prefix;
  char *dst = clean_prefix;
  size_t dst_len = 0;

  while (*src && dst_len < sizeof(clean_prefix) - 1) {
    if (*src != '[' && *src != ']') {
      // Skip leading/trailing spaces
      if (*src == ' ' &&
          (dst == clean_prefix || *(src + 1) == '\0' || *(src + 1) == ' ')) {
        src++;
        continue;
      }
      *dst++ = *src;
      dst_len++;
    }
    src++;
  }
  *dst = '\0';

  // Trim trailing spaces
  while (dst > clean_prefix && *(dst - 1) == ' ') {
    *(--dst) = '\0';
  }

  // Print to stdout
  pthread_mutex_lock(&log_mutex);
  printf("%s [%s] ", time_str, clean_prefix);
  va_start(args, format);
  vprintf(format, args);
  va_end(args);

  // Handle newline
  size_t len = strlen(format);
  if (len == 0 || format[len - 1] != '\n') {
    printf("\n");
  }
  fflush(stdout);

#ifdef __ANDROID__
  va_start(args, format);
  int priority = ANDROID_LOG_INFO;
  if (strstr(prefix, "ERROR") || strstr(format, "❌"))
    priority = ANDROID_LOG_ERROR;
  else if (strstr(prefix, "WARN") || strstr(format, "⚠️"))
    priority = ANDROID_LOG_WARN;
  else if (strstr(prefix, "DEBUG") || strstr(format, "🔍"))
    priority = ANDROID_LOG_DEBUG;

  __android_log_vprint(priority, "Wawona", format, args);
  va_end(args);
#endif

  // Print to log file
  if (compositor_log_file) {
    fprintf(compositor_log_file, "%s [%s] ", time_str, clean_prefix);
    va_start(args, format);
    vfprintf(compositor_log_file, format, args);
    va_end(args);
    if (len == 0 || format[len - 1] != '\n') {
      fprintf(compositor_log_file, "\n");
    }
    fflush(compositor_log_file);
  }
  pthread_mutex_unlock(&log_mutex);
}

void log_fflush(void) {
  fflush(stdout);
  if (compositor_log_file)
    fflush(compositor_log_file);
  if (client_log_file)
    fflush(client_log_file);
}

void cleanup_logging(void) {
  if (compositor_log_file) {
    fclose(compositor_log_file);
    compositor_log_file = NULL;
  }
  if (client_log_file) {
    fclose(client_log_file);
    client_log_file = NULL;
  }
}
