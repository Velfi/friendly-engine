const std = @import("std");

pub const Kind = enum {
    none,
    select_box,
    draw_face,
    draw_profile,
    draw_path,
    extrude,
    solidify,
    revolve,
    cut,
    inset,
    bevel,
    shape_handle,
    marker_place,
};

pub const Phase = enum {
    idle,
    preview,
    dragging,
    committed,
    cancelled,
};

pub const Gesture = struct {
    kind: Kind = .none,
    phase: Phase = .idle,
    numeric_override: ?f32 = null,

    pub fn begin(self: *Gesture, kind: Kind) void {
        self.* = .{ .kind = kind, .phase = .preview };
    }

    pub fn drag(self: *Gesture) void {
        if (self.kind == .none) return;
        self.phase = .dragging;
    }

    pub fn commit(self: *Gesture) void {
        if (self.kind == .none) return;
        self.phase = .committed;
    }

    pub fn cancel(self: *Gesture) void {
        if (self.kind == .none) return;
        self.phase = .cancelled;
    }

    pub fn reset(self: *Gesture) void {
        self.* = .{};
    }
};

test "gesture lifecycle is explicit" {
    var gesture = Gesture{};
    gesture.begin(.draw_face);
    try std.testing.expectEqual(Phase.preview, gesture.phase);
    gesture.drag();
    try std.testing.expectEqual(Phase.dragging, gesture.phase);
    gesture.commit();
    try std.testing.expectEqual(Phase.committed, gesture.phase);
}
