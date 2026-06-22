#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FeXatlasInput {
    const float *positions;
    const float *normals;
    const uint32_t *indices;
    const uint32_t *face_materials;
    uint32_t vertex_count;
    uint32_t position_stride;
    uint32_t normal_stride;
    uint32_t index_count;
    uint32_t face_count;
} FeXatlasInput;

typedef struct FeXatlasOptions {
    uint32_t atlas_size;
    uint32_t padding_px;
    uint32_t max_iterations;
    float texels_per_unit;
    float max_chart_area;
    float normal_seam_weight;
} FeXatlasOptions;

typedef struct FeXatlasVertex {
    int32_t atlas_index;
    int32_t chart_index;
    float uv[2];
    uint32_t xref;
} FeXatlasVertex;

typedef struct FeXatlasOutput {
    void *atlas;
    const FeXatlasVertex *vertices;
    const uint32_t *indices;
    uint32_t vertex_count;
    uint32_t index_count;
    uint32_t chart_count;
    uint32_t atlas_width;
    uint32_t atlas_height;
    uint32_t atlas_count;
    float utilization;
    float texels_per_unit;
    int32_t error_code;
} FeXatlasOutput;

enum {
    FE_XATLAS_OK = 0,
    FE_XATLAS_ERROR = 1,
    FE_XATLAS_INDEX_OUT_OF_RANGE = 2,
    FE_XATLAS_INVALID_FACE_VERTEX_COUNT = 3,
    FE_XATLAS_INVALID_INDEX_COUNT = 4,
    FE_XATLAS_MISSING_OUTPUT_MESH = 5,
};

FeXatlasOutput fe_xatlas_generate(const FeXatlasInput *input, const FeXatlasOptions *options);
void fe_xatlas_destroy(void *atlas);
const char *fe_xatlas_commit(void);

#ifdef __cplusplus
}
#endif
