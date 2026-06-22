const std = @import("std");

pub const Job = struct {
    context: *anyopaque,
    run: *const fn (context: *anyopaque) void,
};

pub const JobQueue = struct {
    allocator: std.mem.Allocator,
    jobs: std.ArrayList(Job),

    pub fn init(allocator: std.mem.Allocator) JobQueue {
        return .{
            .allocator = allocator,
            .jobs = .empty,
        };
    }

    pub fn deinit(self: *JobQueue) void {
        self.jobs.deinit(self.allocator);
    }

    pub fn schedule(self: *JobQueue, job: Job) !void {
        try self.jobs.append(self.allocator, job);
    }

    pub fn runAll(self: *JobQueue) void {
        for (self.jobs.items) |job| {
            job.run(job.context);
        }
        self.jobs.clearRetainingCapacity();
    }
};

pub fn parallelFor(
    comptime Context: type,
    context: *Context,
    count: usize,
    task: *const fn (ctx: *Context, index: usize) void,
) void {
    // First SDK cut keeps scheduling deterministic; execution policy can be swapped later.
    var i: usize = 0;
    while (i < count) : (i += 1) {
        task(context, i);
    }
}

const JobTestState = struct {
    value: usize = 0,
};

fn incrementJob(context: *anyopaque) void {
    const state: *JobTestState = @ptrCast(@alignCast(context));
    state.value += 1;
}

fn addIndexTask(state: *usize, index: usize) void {
    state.* += index;
}

test "job queue schedules and executes work" {
    var queue = JobQueue.init(std.testing.allocator);
    defer queue.deinit();

    var state = JobTestState{};
    try queue.schedule(.{
        .context = &state,
        .run = incrementJob,
    });
    try queue.schedule(.{
        .context = &state,
        .run = incrementJob,
    });

    queue.runAll();
    try std.testing.expectEqual(@as(usize, 2), state.value);
    try std.testing.expectEqual(@as(usize, 0), queue.jobs.items.len);
}

test "parallel for iterates full range" {
    var sum: usize = 0;
    parallelFor(usize, &sum, 4, addIndexTask);
    try std.testing.expectEqual(@as(usize, 6), sum);
}
