#include "fe_plutosvg_bridge.h"

#include <plutosvg.h>

#include <string.h>

enum {
    FE_SVG_OK = 0,
    FE_SVG_INVALID_ARGUMENT = 1,
    FE_SVG_LOAD_FAILED = 2,
    FE_SVG_RENDER_FAILED = 3,
};

int fe_svg_render_rgba(const char* svg_data, int svg_len, int width, int height, unsigned char* out_rgba, int out_len)
{
    if(svg_data == 0 || svg_len <= 0 || width <= 0 || height <= 0 || out_rgba == 0) {
        return FE_SVG_INVALID_ARGUMENT;
    }

    const int expected_len = width * height * 4;
    if(out_len < expected_len) {
        return FE_SVG_INVALID_ARGUMENT;
    }

    memset(out_rgba, 0, (size_t)expected_len);

    plutosvg_document_t* document = plutosvg_document_load_from_data(svg_data, svg_len, (float)width, (float)height, 0, 0);
    if(document == 0) {
        return FE_SVG_LOAD_FAILED;
    }

    plutovg_color_t current_color;
    plutovg_color_init_rgba8(&current_color, 255, 255, 255, 255);

    plutovg_rect_t extents = {0, 0, (float)width, (float)height};
    if(!plutosvg_document_extents(document, 0, &extents) || extents.w <= 0.f || extents.h <= 0.f) {
        plutosvg_document_destroy(document);
        return FE_SVG_RENDER_FAILED;
    }

    plutovg_surface_t* surface = plutovg_surface_create(width, height);
    if(surface == 0) {
        plutosvg_document_destroy(document);
        return FE_SVG_RENDER_FAILED;
    }

    plutovg_color_t transparent;
    plutovg_color_init_rgba8(&transparent, 0, 0, 0, 0);
    plutovg_surface_clear(surface, &transparent);

    plutovg_canvas_t* canvas = plutovg_canvas_create(surface);
    if(canvas == 0) {
        plutovg_surface_destroy(surface);
        plutosvg_document_destroy(document);
        return FE_SVG_RENDER_FAILED;
    }

    plutovg_canvas_scale(canvas, width / extents.w, height / extents.h);
    plutovg_canvas_translate(canvas, -extents.x, -extents.y);
    const bool rendered_ok = plutosvg_document_render(document, 0, canvas, &current_color, 0, 0);
    plutovg_canvas_destroy(canvas);
    plutosvg_document_destroy(document);
    if(!rendered_ok) {
        plutovg_surface_destroy(surface);
        return FE_SVG_RENDER_FAILED;
    }

    plutovg_convert_argb_to_rgba(out_rgba, plutovg_surface_get_data(surface), width, height, plutovg_surface_get_stride(surface));

    plutovg_surface_destroy(surface);
    return FE_SVG_OK;
}
