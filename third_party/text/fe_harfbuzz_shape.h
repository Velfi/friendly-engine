#ifndef FE_HARFBUZZ_SHAPE_H
#define FE_HARFBUZZ_SHAPE_H

#include <stdint.h>

typedef struct FeHbGlyph {
    uint32_t glyph_id;
    uint32_t cluster;
    int32_t x_advance;
    int32_t y_advance;
    int32_t x_offset;
    int32_t y_offset;
} FeHbGlyph;

int fe_hb_shape_utf8(
    const unsigned char* font_data,
    int font_len,
    const char* text,
    int text_len,
    FeHbGlyph* out_glyphs,
    int out_capacity,
    int* out_count
);

#endif
