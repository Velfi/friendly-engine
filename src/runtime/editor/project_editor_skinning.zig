const shared = @import("runtime_shared");
const project_editor_state = @import("project_editor_state.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn refreshSkinning(state: *ProjectEditorState) void {
    for (state.objects.items) |*obj| {
        if (obj.mesh.skin == null) continue;
        const asset = obj.skeleton_asset orelse continue;
        const skeleton = shared.scene_skinning.findSkeletonForAsset(state.skeletons.items, asset) orelse continue;
        shared.scene_skinning.deformMesh(&obj.mesh, skeleton, obj.bone_pose);
    }
}
