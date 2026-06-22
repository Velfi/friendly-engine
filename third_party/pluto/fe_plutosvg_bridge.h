#ifndef FE_PLUTOSVG_BRIDGE_H
#define FE_PLUTOSVG_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

int fe_svg_render_rgba(const char* svg_data, int svg_len, int width, int height, unsigned char* out_rgba, int out_len);

#ifdef __cplusplus
}
#endif

#endif
