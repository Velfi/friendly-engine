const prop_catalog = @import("project_editor_prop_catalog.zig");
const placement = @import("project_editor_prop_placement.zig");
const instantiate = @import("project_editor_prop_instantiate.zig");
const recent = @import("project_editor_prop_recent.zig");
const edit = @import("project_editor_prop_edit.zig");
const open = @import("project_editor_prop_open.zig");
const asset = @import("project_editor_prop_asset.zig");

pub const cache_target = prop_catalog.cache_target;
pub const max_recent_props = prop_catalog.max_recent_props;
pub const CatalogEntry = prop_catalog.CatalogEntry;
pub const catalog = prop_catalog.catalog;

pub const findCatalogEntry = prop_catalog.findCatalogEntry;
pub const catalogLabel = prop_catalog.catalogLabel;
pub const layerLabel = prop_catalog.layerLabel;
pub const objectNameById = prop_catalog.objectNameById;
pub const objectIndexById = prop_catalog.objectIndexById;
pub const resolveParentId = prop_catalog.resolveParentId;
pub const primitiveLabel = prop_catalog.primitiveLabel;

pub const placementPoint = placement.placementPoint;
pub const refreshPlacementPreview = placement.refreshPlacementPreview;
pub const placeAtScreen = placement.placeAtScreen;
pub const instantiatePropAsset = placement.instantiatePropAsset;
pub const instantiatePropAssetAt = instantiate.instantiatePropAssetAt;
pub const addPrimitiveProp = instantiate.addPrimitiveProp;
pub const placePrimitiveProp = instantiate.placePrimitiveProp;
pub const openAssetForEditing = open.openAssetForEditing;
pub const setOpenAssetErrorDetail = open.setOpenAssetErrorDetail;
pub const placeSketchPointAtScreen = asset.placeSketchPointAtScreen;
pub const selectedAssetId = asset.selectedAssetId;
pub const propagateSelectedAssetGeometry = asset.propagateSelectedAssetGeometry;
pub const propagateSelectedAssetGeometryFallible = asset.propagateSelectedAssetGeometryFallible;
pub const regenerateSelectedFromRecipe = asset.regenerateSelectedFromRecipe;
pub const taperSelected = asset.taperSelected;
pub const mirrorSelectedX = asset.mirrorSelectedX;
pub const arraySelectedX = asset.arraySelectedX;
pub const extrudePathSelected = asset.extrudePathSelected;
pub const solidifySelected = asset.solidifySelected;
pub const revolveSelected = asset.revolveSelected;
pub const insetSelected = asset.insetSelected;
pub const bevelSelected = asset.bevelSelected;
pub const cutSelected = asset.cutSelected;

pub const invalidatePropPreviewMesh = recent.invalidatePropPreviewMesh;
pub const rebuildRecentFromObjects = recent.rebuildRecentFromObjects;
pub const recordRecentProp = recent.recordRecentProp;

pub const cycleSelectedVariant = edit.cycleSelectedVariant;
pub const setTrigger = edit.setTrigger;
pub const setInteractable = edit.setInteractable;
pub const setGameplayTag = edit.setGameplayTag;
pub const setParentId = edit.setParentId;
pub const setLayer = edit.setLayer;

comptime {
    _ = @import("project_editor_prop_tests.zig");
}
