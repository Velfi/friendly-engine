const std = @import("std");

pub const Kind = enum {
    player_start,
    checkpoint,
    spawn_point,
    encounter_spawn,
    item_spawn,
    objective,
    interactable_anchor,
    trigger_volume,
    camera_point,
    audio_emitter,
    nav_point,
    patrol_point,
    region_anchor,

    pub fn label(self: Kind) []const u8 {
        return switch (self) {
            .player_start => "Player Start",
            .checkpoint => "Checkpoint",
            .spawn_point => "Spawn Point",
            .encounter_spawn => "Encounter Spawn",
            .item_spawn => "Item Spawn",
            .objective => "Objective",
            .interactable_anchor => "Interactable Anchor",
            .trigger_volume => "Trigger Volume",
            .camera_point => "Camera Point",
            .audio_emitter => "Audio Emitter",
            .nav_point => "Nav Point",
            .patrol_point => "Patrol Point",
            .region_anchor => "Region Anchor",
        };
    }

    pub fn name(self: Kind) []const u8 {
        return @tagName(self);
    }

    pub fn fromName(value: []const u8) ?Kind {
        inline for (std.meta.fields(Kind)) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }
};

pub const Shape = enum {
    point,
    box,
    sphere,
    path,

    pub fn name(self: Shape) []const u8 {
        return @tagName(self);
    }

    pub fn fromName(value: []const u8) ?Shape {
        inline for (std.meta.fields(Shape)) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }
};

pub const Marker = struct {
    kind: Kind,
    shape: Shape = .point,
    marker_id: []u8 = "",
    group: []u8 = "",
    binding: []u8 = "",
    radius: f32 = 1.0,
    order: i32 = 0,

    pub fn deinit(self: *Marker, allocator: std.mem.Allocator) void {
        if (self.marker_id.len > 0) allocator.free(self.marker_id);
        if (self.group.len > 0) allocator.free(self.group);
        if (self.binding.len > 0) allocator.free(self.binding);
        self.* = .{ .kind = .player_start };
    }

    pub fn duplicate(allocator: std.mem.Allocator, source: Marker) !Marker {
        return .{
            .kind = source.kind,
            .shape = source.shape,
            .marker_id = if (source.marker_id.len > 0) try allocator.dupe(u8, source.marker_id) else "",
            .group = if (source.group.len > 0) try allocator.dupe(u8, source.group) else "",
            .binding = if (source.binding.len > 0) try allocator.dupe(u8, source.binding) else "",
            .radius = source.radius,
            .order = source.order,
        };
    }

    pub fn validate(self: Marker) !void {
        if (self.radius <= 0 or !std.math.isFinite(self.radius)) return error.InvalidMarkerRadius;
        switch (self.kind) {
            .player_start => {
                if (self.binding.len == 0) return error.MissingMarkerBinding;
            },
            .objective, .checkpoint, .region_anchor => {
                if (self.marker_id.len == 0) return error.MissingMarkerId;
            },
            .patrol_point => {
                if (self.group.len == 0) return error.MissingMarkerGroup;
            },
            else => {},
        }
    }
};

pub fn defaultForKind(allocator: std.mem.Allocator, kind: Kind) !Marker {
    return .{
        .kind = kind,
        .shape = switch (kind) {
            .trigger_volume, .region_anchor => .box,
            .audio_emitter => .sphere,
            .patrol_point, .nav_point => .path,
            else => .point,
        },
        .marker_id = switch (kind) {
            .player_start => try allocator.dupe(u8, "player_start"),
            .objective => try allocator.dupe(u8, "objective"),
            .checkpoint => try allocator.dupe(u8, "checkpoint"),
            .region_anchor => try allocator.dupe(u8, "region"),
            else => "",
        },
        .group = switch (kind) {
            .spawn_point, .encounter_spawn => try allocator.dupe(u8, "default"),
            .patrol_point => try allocator.dupe(u8, "patrol"),
            else => "",
        },
        .binding = switch (kind) {
            .player_start => try allocator.dupe(u8, "controller:fps"),
            .camera_point => try allocator.dupe(u8, "startup"),
            .audio_emitter => try allocator.dupe(u8, "event"),
            else => "",
        },
        .radius = switch (kind) {
            .trigger_volume, .region_anchor => 2.0,
            .audio_emitter => 8.0,
            else => 1.0,
        },
    };
}

test "marker validation catches required gameplay data" {
    var marker = Marker{ .kind = .player_start };
    try std.testing.expectError(error.MissingMarkerBinding, marker.validate());
    marker.binding = @constCast("controller:fps");
    try marker.validate();
}

test "default marker is owned and duplicable" {
    var marker = try defaultForKind(std.testing.allocator, .objective);
    defer marker.deinit(std.testing.allocator);
    try marker.validate();
    var copy = try Marker.duplicate(std.testing.allocator, marker);
    defer copy.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(marker.marker_id, copy.marker_id);
}

test "default marker validates every gameplay kind" {
    inline for (std.meta.fields(Kind)) |field| {
        var marker = try defaultForKind(std.testing.allocator, @enumFromInt(field.value));
        defer marker.deinit(std.testing.allocator);
        try marker.validate();
    }
}
