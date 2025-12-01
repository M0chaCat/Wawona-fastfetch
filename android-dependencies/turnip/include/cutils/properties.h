#ifndef ANDROID_CUTILS_PROPERTIES_H
#define ANDROID_CUTILS_PROPERTIES_H
#include <string.h>
#define PROPERTY_VALUE_MAX 128
static inline int property_get(const char* key, char* value, const char* default_value) { (void)key; if (value && default_value) { strncpy(value, default_value, PROPERTY_VALUE_MAX-1); value[PROPERTY_VALUE_MAX-1] = '\0'; return (int)strlen(value); } return 0; }
#endif
