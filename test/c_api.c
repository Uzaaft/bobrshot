#include "bobrshot.h"

#include <stdint.h>

_Static_assert(sizeof(BobrshotVersion) == 6, "BobrshotVersion ABI changed");
_Static_assert(sizeof(BobrshotImageFormat) == 1,
               "BobrshotImageFormat ABI changed");

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

  return 0;
}
