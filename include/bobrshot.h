#ifndef BOBRSHOT_H
#define BOBRSHOT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BobrshotVersion {
  uint16_t major;
  uint16_t minor;
  uint16_t patch;
} BobrshotVersion;

typedef uint8_t BobrshotImageFormat;

static const BobrshotImageFormat BobrshotImageFormatUnknown = 0;
static const BobrshotImageFormat BobrshotImageFormatPNG = 1;
static const BobrshotImageFormat BobrshotImageFormatJPEG = 2;
static const BobrshotImageFormat BobrshotImageFormatGIF = 3;
static const BobrshotImageFormat BobrshotImageFormatWebP = 4;
static const BobrshotImageFormat BobrshotImageFormatTIFF = 5;
static const BobrshotImageFormat BobrshotImageFormatHEIC = 6;
static const BobrshotImageFormat BobrshotImageFormatHEIF = 7;

BobrshotVersion bobrshot_core_version(void);
BobrshotImageFormat bobrshot_image_format_detect(const uint8_t *bytes,
                                                  size_t length);

#ifdef __cplusplus
}
#endif

#endif
