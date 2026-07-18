#ifndef BOBRSHOT_H
#define BOBRSHOT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BobrshotVersion {
  uint16_t major;
  uint16_t minor;
  uint16_t patch;
} BobrshotVersion;

BobrshotVersion bobrshot_core_version(void);

#ifdef __cplusplus
}
#endif

#endif
