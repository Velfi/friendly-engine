#include "fe_xatlas_bridge.h"

#include "source/xatlas/xatlas.h"

static int32_t map_add_mesh_error(xatlas::AddMeshError error) {
    switch (error) {
    case xatlas::AddMeshError::Success:
        return FE_XATLAS_OK;
    case xatlas::AddMeshError::IndexOutOfRange:
        return FE_XATLAS_INDEX_OUT_OF_RANGE;
    case xatlas::AddMeshError::InvalidFaceVertexCount:
        return FE_XATLAS_INVALID_FACE_VERTEX_COUNT;
    case xatlas::AddMeshError::InvalidIndexCount:
        return FE_XATLAS_INVALID_INDEX_COUNT;
    case xatlas::AddMeshError::Error:
    default:
        return FE_XATLAS_ERROR;
    }
}

FeXatlasOutput fe_xatlas_generate(const FeXatlasInput *input, const FeXatlasOptions *options) {
    FeXatlasOutput output = {};
    xatlas::Atlas *atlas = xatlas::Create();
    if (!atlas) {
        output.error_code = FE_XATLAS_ERROR;
        return output;
    }

    xatlas::MeshDecl mesh = {};
    mesh.vertexPositionData = input->positions;
    mesh.vertexNormalData = input->normals;
    mesh.indexData = input->indices;
    mesh.faceMaterialData = input->face_materials;
    mesh.vertexCount = input->vertex_count;
    mesh.vertexPositionStride = input->position_stride;
    mesh.vertexNormalStride = input->normal_stride;
    mesh.indexCount = input->index_count;
    mesh.faceCount = input->face_count;
    mesh.indexFormat = xatlas::IndexFormat::UInt32;

    const xatlas::AddMeshError add_error = xatlas::AddMesh(atlas, mesh);
    if (add_error != xatlas::AddMeshError::Success) {
        output.error_code = map_add_mesh_error(add_error);
        xatlas::Destroy(atlas);
        return output;
    }

    xatlas::ChartOptions chart_options;
    chart_options.maxChartArea = options->max_chart_area;
    chart_options.normalSeamWeight = options->normal_seam_weight;
    chart_options.maxIterations = options->max_iterations;
    chart_options.fixWinding = true;

    xatlas::PackOptions pack_options;
    pack_options.padding = options->padding_px;
    pack_options.texelsPerUnit = options->texels_per_unit;
    pack_options.resolution = options->atlas_size;
    pack_options.bruteForce = true;
    pack_options.rotateCharts = true;
    pack_options.rotateChartsToAxis = true;

    xatlas::Generate(atlas, chart_options, pack_options);

    if (atlas->meshCount == 0 || !atlas->meshes) {
        output.error_code = FE_XATLAS_MISSING_OUTPUT_MESH;
        xatlas::Destroy(atlas);
        return output;
    }

    const xatlas::Mesh &out_mesh = atlas->meshes[0];
    output.atlas = atlas;
    output.vertices = reinterpret_cast<const FeXatlasVertex *>(out_mesh.vertexArray);
    output.indices = out_mesh.indexArray;
    output.vertex_count = out_mesh.vertexCount;
    output.index_count = out_mesh.indexCount;
    output.chart_count = atlas->chartCount;
    output.atlas_width = atlas->width;
    output.atlas_height = atlas->height;
    output.atlas_count = atlas->atlasCount;
    output.utilization = atlas->utilization ? atlas->utilization[0] : 0.0f;
    output.texels_per_unit = atlas->texelsPerUnit;
    output.error_code = FE_XATLAS_OK;
    return output;
}

void fe_xatlas_destroy(void *atlas) {
    xatlas::Destroy(static_cast<xatlas::Atlas *>(atlas));
}

const char *fe_xatlas_commit(void) {
    return "f700c7790aaa030e794b52ba7791a05c085faf0c";
}
