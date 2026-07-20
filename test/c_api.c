#include "bobrshot.h"

#include <stdint.h>
#include <stddef.h>

_Static_assert(sizeof(BobrshotVersion) == 6, "BobrshotVersion ABI changed");
_Static_assert(sizeof(BobrshotImageFormat) == 1,
               "BobrshotImageFormat ABI changed");
_Static_assert(sizeof(BobrshotOptimizeRequestV1) == 32,
               "BobrshotOptimizeRequestV1 ABI changed");
_Static_assert(offsetof(BobrshotOptimizeRequestV1, input_bytes) == 8,
               "BobrshotOptimizeRequestV1 layout changed");
_Static_assert(offsetof(BobrshotOptimizeRequestV1, output_format) == 24,
               "BobrshotOptimizeRequestV1 layout changed");
_Static_assert(sizeof(BobrshotImageDescriptorV1) == 20,
               "BobrshotImageDescriptorV1 ABI changed");

int main(void) {
  const uint8_t png[] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
  const uint8_t video[] = {0x00, 0x00, 0x00, 0x18, 'f', 't', 'y', 'p',
                           'i',  's',  'o',  'm'};

  if (bobrshot_image_format_detect(png, sizeof(png)) !=
      BobrshotImageFormatPNG)
    return 1;
  if (bobrshot_image_format_detect(video, sizeof(video)) !=
      BobrshotImageFormatUnknown)
    return 2;
  if (bobrshot_image_format_detect(NULL, 0) != BobrshotImageFormatUnknown)
    return 3;

  BobrshotOptimizeRequestV1 request = {
      .struct_size = sizeof(request),
      .flags = BobrshotOptimizeFlagOnlyIfSmaller,
      .input_bytes = png,
      .input_length = sizeof(png),
      .output_format = BobrshotImageFormatUnknown,
  };
  size_t output_length = 99;
  BobrshotImageFormat output_format = 99;
  if (bobrshot_image_optimize_v1(&request, NULL, 0, &output_length,
                                 &output_format) !=
      BobrshotStatusInvalidData)
    return 4;
  if (output_length != 0 || output_format != BobrshotImageFormatUnknown)
    return 5;

  request.input_bytes = (const uint8_t *)"GIF89aencoded";
  request.input_length = 13;
  if (bobrshot_image_optimize_v1(&request, NULL, 0, &output_length,
                                 &output_format) != BobrshotStatusOK)
    return 6;
  if (output_length != request.input_length)
    return 7;
  if (output_format != BobrshotImageFormatGIF)
    return 8;

  uint8_t output[13];
  if (bobrshot_image_optimize_v1(&request, output, sizeof(output),
                                 &output_length,
                                 &output_format) != BobrshotStatusOK)
    return 9;

  return 0;
}
