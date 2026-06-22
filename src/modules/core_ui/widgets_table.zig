const std = @import("std");
const commands = @import("commands.zig");
const context = @import("context.zig");
const input = @import("input.zig");
const layout = @import("layout.zig");

pub const TableRow = struct {
    cells: []const []const u8,
};

pub const TableOptions = struct {
    id: []const u8,
    columns: []const []const u8,
    column_widths: ?[]const f32 = null,
    rows: []const TableRow,
    sort_column: *i32,
    sort_asc: *bool,
    selected_row: ?*i32 = null,
    height: ?f32 = null,
};

const header_height: f32 = 24.0;
const row_height: f32 = 22.0;

pub fn table(ui: *context.UiContext, options: TableOptions) !void {
    if (options.columns.len == 0) return error.EmptyTableColumns;

    const table_stable = try ui.stableId(options.id, options.id);
    const cursor = try ui.currentLayout();
    const content_w = cursor.content_w;
    const content_x = cursor.content_x;
    const row_y = cursor.cursor_y - cursor.scroll_y;

    var widths: [32]f32 = undefined;
    if (options.columns.len > widths.len) return error.TooManyTableColumns;
    computeColumnWidths(content_w, options.columns.len, options.column_widths, &widths);

    var col_x = content_x;
    for (options.columns, 0..) |column, column_index| {
        const col_w = widths[column_index];
        const cell_rect = context.Rect{
            .x = col_x,
            .y = row_y,
            .w = col_w,
            .h = header_height,
        };
        const header_stable = try ui.stableId(options.id, column);
        const click = input.handleClick(ui, header_stable, cell_rect);
        const sort_active = options.sort_column.* == @as(i32, @intCast(column_index));
        if (click.clicked) {
            if (!sort_active) {
                options.sort_column.* = @intCast(column_index);
                options.sort_asc.* = true;
            } else if (options.sort_asc.*) {
                options.sort_asc.* = false;
            } else {
                options.sort_column.* = -1;
                options.sort_asc.* = true;
            }
        }

        var header_text_buf: [128]u8 = undefined;
        const header_text = try ui.dupeText(try formatHeaderText(
            &header_text_buf,
            column,
            sort_active,
            options.sort_asc.*,
        ));

        try ui.pushCommand(.{
            .table_header_cell = .{
                .id = ui.nextCommandId(header_stable),
                .table_id = table_stable,
                .rect = cell_rect,
                .text = header_text,
                .column_index = @intCast(column_index),
                .sort_active = sort_active,
                .sort_asc = options.sort_asc.*,
                .hovered = click.hovered,
                .active = click.active,
            },
        });
        col_x += col_w;
    }
    cursor.cursor_y += header_height + cursor.spacing;

    const use_scroll = options.height != null;
    if (use_scroll) {
        var scroll_id_buf: [128]u8 = undefined;
        const scroll_id = try std.fmt.bufPrint(&scroll_id_buf, "{s}/scroll", .{options.id});
        try layout.beginScrollArea(ui, .{
            .id = scroll_id,
            .height = options.height.?,
        });
    }

    for (options.rows, 0..) |row, row_index| {
        if (row.cells.len != options.columns.len) return error.TableRowColumnMismatch;

        const row_rect = try ui.allocFullWidthRow(row_height);
        var row_id_buf: [64]u8 = undefined;
        const row_id = try std.fmt.bufPrint(&row_id_buf, "row/{d}", .{row_index});
        const row_stable = try ui.stableId(options.id, row_id);
        const row_click = input.handleClick(ui, row_stable, row_rect);
        var selected = if (options.selected_row) |selected_row|
            selected_row.* == @as(i32, @intCast(row_index))
        else
            false;
        if (row_click.clicked) {
            if (options.selected_row) |selected_row| {
                selected_row.* = @intCast(row_index);
                selected = true;
            }
        }

        try ui.pushCommand(.{
            .table_row = .{
                .id = ui.nextCommandId(row_stable),
                .table_id = table_stable,
                .rect = row_rect,
                .row_index = @intCast(row_index),
                .selected = selected,
                .hovered = row_click.hovered,
                .active = row_click.active,
            },
        });

        col_x = content_x;
        for (row.cells, 0..) |cell_text, column_index| {
            const cell_rect = context.Rect{
                .x = col_x,
                .y = row_rect.y,
                .w = widths[column_index],
                .h = row_rect.h,
            };
            const cell_stable = try ui.stableId(cell_text, cell_text);
            try ui.pushCommand(.{
                .table_cell = .{
                    .id = ui.nextCommandId(cell_stable),
                    .table_id = table_stable,
                    .row_id = row_stable,
                    .rect = cell_rect,
                    .text = try ui.dupeText(cell_text),
                },
            });
            col_x += widths[column_index];
        }
    }

    if (use_scroll) try layout.endScrollArea(ui);
}

fn computeColumnWidths(content_w: f32, count: usize, explicit: ?[]const f32, out: []f32) void {
    if (explicit) |widths| {
        var total: f32 = 0.0;
        for (0..count) |i| {
            const w = if (i < widths.len) widths[i] else 1.0;
            out[i] = w;
            total += w;
        }
        const scale = if (total > 0.0) content_w / total else content_w / @as(f32, @floatFromInt(count));
        for (0..count) |i| out[i] *= scale;
        return;
    }

    const equal = content_w / @as(f32, @floatFromInt(count));
    for (0..count) |i| out[i] = equal;
}

fn formatHeaderText(buf: []u8, column: []const u8, sort_active: bool, sort_asc: bool) ![]const u8 {
    if (!sort_active) return column;
    const indicator: []const u8 = if (sort_asc) " ^" else " v";
    return std.fmt.bufPrint(buf, "{s}{s}", .{ column, indicator });
}

test "table header toggles sort column" {
    var ui = context.UiContext.init(std.testing.allocator);
    defer ui.deinit();

    const rows = [_]TableRow{
        .{ .cells = &.{ "Cube", "Mesh", "12" } },
        .{ .cells = &.{ "Light", "Point", "4" } },
    };
    var sort_col: i32 = -1;
    var sort_asc: bool = true;

    ui.beginFrame(.{
        .mouse_position = .{ .x = 30, .y = 14 },
        .primary_pressed = true,
    });
    try layout.beginPanel(&ui, .{ .id = "panel", .rect = .{ .x = 0, .y = 0, .w = 240, .h = 160 } });
    try table(&ui, .{
        .id = "assets",
        .columns = &.{ "Name", "Type", "Size" },
        .rows = &rows,
        .sort_column = &sort_col,
        .sort_asc = &sort_asc,
    });
    layout.endPanel(&ui);

    ui.beginFrame(.{
        .mouse_position = .{ .x = 30, .y = 14 },
        .primary_released = true,
    });
    ui.active_widget = try ui.stableId("assets", "Name");
    try layout.beginPanel(&ui, .{ .id = "panel", .rect = .{ .x = 0, .y = 0, .w = 240, .h = 160 } });
    try table(&ui, .{
        .id = "assets",
        .columns = &.{ "Name", "Type", "Size" },
        .rows = &rows,
        .sort_column = &sort_col,
        .sort_asc = &sort_asc,
    });
    layout.endPanel(&ui);

    try std.testing.expectEqual(@as(i32, 0), sort_col);
    try std.testing.expect(sort_asc);
}
