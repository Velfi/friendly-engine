const std = @import("std");
const buildings = @import("mod.zig");

const BuildingDef = buildings.BuildingDef;
const DoorDef = buildings.DoorDef;
const WindowDef = buildings.WindowDef;

pub const BuildingKind = enum {
    shell,
    house,
    shop,
    apartment,
};

pub const SemanticBuildingDescriptor = struct {
    id: []const u8,
    cell: [3]i32,
    kind: BuildingKind = .shell,
    origin: [2]f32,
    size: [2]f32,
    floors: u32 = 1,
    doors: []const DoorDef = &.{},
    windows: []const WindowDef = &.{},
};

pub const BuildingDescriptor = SemanticBuildingDescriptor;

pub const BuildingFootprintScratch = struct {
    cell: [3]i32 = undefined,
    points: [4][2]f32 = undefined,
    slices: [4][]const f32 = undefined,
};

pub fn makeRectangularBuilding(
    scratch: *BuildingFootprintScratch,
    descriptor: SemanticBuildingDescriptor,
) !BuildingDef {
    try buildings.validateSemanticBuildingDescriptor(descriptor);
    scratch.cell = descriptor.cell;
    const x0 = descriptor.origin[0];
    const z0 = descriptor.origin[1];
    const x1 = x0 + descriptor.size[0];
    const z1 = z0 + descriptor.size[1];
    scratch.points = .{
        .{ x0, z0 },
        .{ x1, z0 },
        .{ x1, z1 },
        .{ x0, z1 },
    };
    for (&scratch.slices, 0..) |*slice, i| {
        slice.* = scratch.points[i][0..];
    }
    const building = BuildingDef{
        .id = descriptor.id,
        .cell = scratch.cell[0..],
        .floors = descriptor.floors,
        .footprint = scratch.slices[0..],
        .doors = descriptor.doors,
        .windows = descriptor.windows,
    };
    try buildings.validateBuilding(building);
    return building;
}
