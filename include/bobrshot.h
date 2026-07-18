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

typedef uint32_t BobrshotStatus;

static const BobrshotStatus BobrshotStatusOK = 0;
static const BobrshotStatus BobrshotStatusInvalidArgument = 1;
static const BobrshotStatus BobrshotStatusInvalidData = 2;
static const BobrshotStatus BobrshotStatusUnsupportedFormat = 3;
static const BobrshotStatus BobrshotStatusLimitExceeded = 4;
static const BobrshotStatus BobrshotStatusOutOfMemory = 5;
static const BobrshotStatus BobrshotStatusEncodeFailed = 6;
static const BobrshotStatus BobrshotStatusInternal = 7;
static const BobrshotStatus BobrshotStatusBufferTooSmall = 8;

typedef uint32_t BobrshotOptimizeFlags;

static const BobrshotOptimizeFlags BobrshotOptimizeFlagOnlyIfSmaller = 1u << 0;
static const BobrshotOptimizeFlags BobrshotOptimizeFlagStripMetadata = 1u << 1;

typedef struct BobrshotOptimizeRequestV1 {
  uint32_t struct_size;
  BobrshotOptimizeFlags flags;
  const uint8_t *input_bytes;
  size_t input_length;
  BobrshotImageFormat output_format;
  uint8_t quality;
  uint8_t effort;
  uint8_t reserved8;
  uint32_t reserved32;
} BobrshotOptimizeRequestV1;

BobrshotVersion bobrshot_core_version(void);
BobrshotImageFormat bobrshot_image_format_detect(const uint8_t *bytes,
                                                  size_t length);
BobrshotStatus
bobrshot_image_optimize_v1(const BobrshotOptimizeRequestV1 *request,
                           uint8_t *output_bytes, size_t output_capacity,
                           size_t *output_length,
                           BobrshotImageFormat *output_format);

#ifdef __cplusplus
}
#endif

#endif
