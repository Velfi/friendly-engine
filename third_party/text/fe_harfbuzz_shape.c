#include "fe_harfbuzz_shape.h"

#include <hb.h>
#include <hb-ot.h>

enum {
    FE_HB_OK = 0,
    FE_HB_INVALID_ARGUMENT = 1,
    FE_HB_ALLOC_FAILED = 2,
    FE_HB_OUTPUT_TOO_SMALL = 3,
};

int fe_hb_shape_utf8(
    const unsigned char* font_data,
    int font_len,
    const char* text,
    int text_len,
    FeHbGlyph* out_glyphs,
    int out_capacity,
    int* out_count
) {
    if(font_data == 0 || font_len <= 0 || text == 0 || text_len < 0 || out_count == 0) {
        return FE_HB_INVALID_ARGUMENT;
    }
    if(out_capacity < 0 || (out_capacity > 0 && out_glyphs == 0)) {
        return FE_HB_INVALID_ARGUMENT;
    }

    *out_count = 0;

    hb_blob_t* blob = hb_blob_create(
        (const char*)font_data,
        (unsigned int)font_len,
        HB_MEMORY_MODE_READONLY,
        0,
        0
    );
    if(blob == 0) return FE_HB_ALLOC_FAILED;

    hb_face_t* face = hb_face_create(blob, 0);
    hb_blob_destroy(blob);
    if(face == 0) return FE_HB_ALLOC_FAILED;

    hb_font_t* font = hb_font_create(face);
    hb_face_destroy(face);
    if(font == 0) return FE_HB_ALLOC_FAILED;

    hb_ot_font_set_funcs(font);

    hb_buffer_t* buffer = hb_buffer_create();
    if(buffer == 0) {
        hb_font_destroy(font);
        return FE_HB_ALLOC_FAILED;
    }

    hb_buffer_add_utf8(buffer, text, text_len, 0, text_len);
    hb_buffer_guess_segment_properties(buffer);
    hb_shape(font, buffer, 0, 0);

    unsigned int glyph_count = 0;
    hb_glyph_info_t* infos = hb_buffer_get_glyph_infos(buffer, &glyph_count);
    hb_glyph_position_t* positions = hb_buffer_get_glyph_positions(buffer, 0);

    *out_count = (int)glyph_count;
    if(glyph_count > (unsigned int)out_capacity) {
        hb_buffer_destroy(buffer);
        hb_font_destroy(font);
        return FE_HB_OUTPUT_TOO_SMALL;
    }

    for(unsigned int i = 0; i < glyph_count; ++i) {
        out_glyphs[i].glyph_id = infos[i].codepoint;
        out_glyphs[i].cluster = infos[i].cluster;
        out_glyphs[i].x_advance = positions[i].x_advance;
        out_glyphs[i].y_advance = positions[i].y_advance;
        out_glyphs[i].x_offset = positions[i].x_offset;
        out_glyphs[i].y_offset = positions[i].y_offset;
    }

    hb_buffer_destroy(buffer);
    hb_font_destroy(font);
    return FE_HB_OK;
}
