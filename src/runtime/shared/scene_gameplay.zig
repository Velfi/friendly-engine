const std = @import("std");

pub const Component = struct {
    tag: []u8 = "",
    health: f32 = 100.0,
    score: i32 = 0,
    team: i32 = 0,
    interactable: bool = false,

    pub fn deinit(self: *Component, allocator: std.mem.Allocator) void {
        allocator.free(self.tag);
        self.tag = "";
    }

    pub fn duplicate(allocator: std.mem.Allocator, source: Component) !Component {
        return .{
            .tag = try allocator.dupe(u8, source.tag),
            .health = source.health,
            .score = source.score,
            .team = source.team,
            .interactable = source.interactable,
        };
    }

    pub fn defaultTag(allocator: std.mem.Allocator) ![]u8 {
        return try allocator.dupe(u8, "player");
    }
};

pub fn parseTag(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    if (text.len == 0) return error.EmptyGameplayTag;
    return try allocator.dupe(u8, text);
}

test "gameplay component duplicates tag" {
    const tag = try std.testing.allocator.dupe(u8, "enemy");
    defer std.testing.allocator.free(tag);
    var copy = try Component.duplicate(std.testing.allocator, .{
        .tag = tag,
        .health = 50,
        .score = 3,
        .team = 1,
    });
    defer copy.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("enemy", copy.tag);
    try std.testing.expectEqual(@as(f32, 50), copy.health);
}

test "gameplay tag parse rejects empty" {
    try std.testing.expectError(error.EmptyGameplayTag, parseTag(std.testing.allocator, ""));
}
