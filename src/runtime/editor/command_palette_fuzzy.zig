const std = @import("std");

pub const label_weight: u32 = 100;
pub const id_weight: u32 = 60;
pub const section_weight: u32 = 40;
pub const screen_weight: u32 = 20;

pub const FieldScores = struct {
    label: u32 = 0,
    id: u32 = 0,
    section: u32 = 0,
    screen: u32 = 0,

    pub fn best(self: FieldScores) u32 {
        return @max(@max(self.label, self.id), @max(self.section, self.screen));
    }
};

pub fn scoreFields(label: []const u8, id: []const u8, section: []const u8, screen: []const u8, query: []const u8) u32 {
    if (query.len == 0) return 1;
    var total: u32 = 0;
    var token_start: usize = 0;
    while (token_start <= query.len) {
        const token_end = nextTokenEnd(query, token_start);
        if (token_end > token_start) {
            const token = query[token_start..token_end];
            const fields = scoreToken(label, id, section, screen, token);
            const best = fields.best();
            if (best == 0) return 0;
            total +%= best;
        }
        if (token_end >= query.len) break;
        token_start = skipSpaces(query, token_end);
    }
    return if (total == 0) 0 else total;
}

pub fn scoreToken(label: []const u8, id: []const u8, section: []const u8, screen: []const u8, token: []const u8) FieldScores {
    return .{
        .label = subsequenceScore(label, token) *% label_weight,
        .id = subsequenceScore(id, token) *% id_weight,
        .section = subsequenceScore(section, token) *% section_weight,
        .screen = subsequenceScore(screen, token) *% screen_weight,
    };
}

pub fn subsequenceScore(text: []const u8, needle: []const u8) u32 {
    if (needle.len == 0) return 1;
    if (needle.len > text.len) return 0;

    var score: u32 = 0;
    var needle_idx: usize = 0;
    var prev_match: ?usize = null;
    var consecutive: u32 = 0;

    for (text, 0..) |ch, i| {
        if (needle_idx >= needle.len) break;
        if (std.ascii.toLower(ch) != std.ascii.toLower(needle[needle_idx])) continue;

        var match_score: u32 = 10;
        if (isWordStart(text, i)) match_score +%= 15;
        if (i > 0 and std.ascii.isUpper(ch) and std.ascii.isLower(text[i - 1])) match_score +%= 10;
        if (prev_match) |prev| {
            if (i == prev + 1) {
                consecutive +%= 1;
                match_score +%= consecutive *% 5;
            } else {
                consecutive = 0;
            }
        }
        score +%= match_score;
        prev_match = i;
        needle_idx += 1;
    }

    if (needle_idx < needle.len) return 0;

    if (startsWithIgnoreCase(text, needle)) score +%= 50;
    if (text.len > 0 and std.ascii.toLower(text[0]) == std.ascii.toLower(needle[0])) score +%= 20;
    return score;
}

fn nextTokenEnd(text: []const u8, start: usize) usize {
    var i = start;
    while (i < text.len and std.ascii.isWhitespace(text[i])) : (i += 1) {}
    const token_start = i;
    while (i < text.len and !std.ascii.isWhitespace(text[i])) : (i += 1) {}
    return if (token_start == i) text.len else i;
}

fn skipSpaces(text: []const u8, start: usize) usize {
    var i = start;
    while (i < text.len and std.ascii.isWhitespace(text[i])) : (i += 1) {}
    return i;
}

fn isWordStart(text: []const u8, index: usize) bool {
    if (index == 0) return true;
    const prev = text[index - 1];
    return !std.ascii.isAlphanumeric(prev);
}

fn startsWithIgnoreCase(text: []const u8, prefix: []const u8) bool {
    if (prefix.len > text.len) return false;
    for (prefix, 0..) |ch, i| {
        if (std.ascii.toLower(text[i]) != std.ascii.toLower(ch)) return false;
    }
    return true;
}

test "subsequence fuzzy matches label tokens" {
    const testing = std.testing;
    try testing.expect(subsequenceScore("Save Scene", "sv") > 0);
    try testing.expect(subsequenceScore("Save Scene", "sc") > 0);
    try testing.expect(scoreFields("Save Scene", "ed-save", "top bar", "Project Editor", "sv sc") > 0);
}

test "subsequence fuzzy matches blockout ramp" {
    const testing = std.testing;
    try testing.expect(scoreFields("Ramp", "ed-blockout-ramp", "left rail", "Project Editor", "blk ramp") > 0);
    try testing.expect(scoreFields("Ramp", "ed-blockout-ramp", "left rail", "Project Editor", "ramp") > 0);
}

test "subsequence fuzzy matches physics and doorway" {
    const testing = std.testing;
    try testing.expect(scoreFields("Static", "ed-physics-static", "inspector", "Project Editor", "phys st") > 0);
    try testing.expect(scoreFields("Doorway", "ed-blockout-doorway", "architecture creation", "Project Editor", "door") > 0);
}

test "no match returns zero" {
    const testing = std.testing;
    try testing.expectEqual(@as(u32, 0), scoreFields("Save", "ed-save", "top bar", "Project Editor", "zzzzz"));
}

test "label match outranks id-only match" {
    const testing = std.testing;
    const label_score = scoreFields("Ramp", "ed-blockout-ramp", "left rail", "Project Editor", "ramp");
    const id_score = scoreFields("Add", "ed-blockout-ramp", "left rail", "Project Editor", "ramp");
    try testing.expect(label_score > id_score);
}
