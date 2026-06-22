const std = @import("std");

pub fn engineJsonSchema(allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator,
        \\{{
        \\  "$schema": "https://json-schema.org/draft/2020-12/schema",
        \\  "title": "Friendly Engine Project Config",
        \\  "type": "object",
        \\  "properties": {{
        \\    "enabled_modules": {{
        \\      "type": "array",
        \\      "items": {{ "type": "string" }}
        \\    }},
        \\    "startup_scene": {{ "type": "string" }},
        \\    "scenes": {{
        \\      "type": "array",
        \\      "items": {{
        \\        "type": "object",
        \\        "properties": {{
        \\          "path": {{ "type": "string" }},
        \\          "world": {{ "type": "string" }}
        \\        }},
        \\        "required": ["path", "world"],
        \\        "additionalProperties": false
        \\      }}
        \\    }},
        \\    "startup_bundle": {{ "type": "string" }}
        \\  }},
        \\  "required": ["enabled_modules", "scenes"],
        \\  "additionalProperties": true
        \\}}
        \\
    , .{});
}

pub fn sceneJsonSchema(allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator,
        \\{{
        \\  "$schema": "https://json-schema.org/draft/2020-12/schema",
        \\  "title": "Friendly Engine Scene",
        \\  "type": "object",
        \\  "properties": {{
        \\    "schema_version": {{ "type": "integer", "minimum": 1 }},
        \\    "next_object_id": {{ "type": "integer", "minimum": 1 }},
        \\    "objects": {{
        \\      "type": "array",
        \\      "items": {{
        \\        "type": "object",
        \\        "properties": {{
        \\          "id": {{ "type": "integer" }},
        \\          "name": {{ "type": "string" }},
        \\          "primitive": {{ "type": "string", "enum": ["box", "plane", "cylinder", "sphere"] }},
        \\          "position": {{ "type": "array", "items": {{ "type": "number" }}, "minItems": 3, "maxItems": 3 }},
        \\          "scale": {{ "type": "array", "items": {{ "type": "number" }}, "minItems": 3, "maxItems": 3 }},
        \\          "base_color": {{ "type": "array", "items": {{ "type": "integer" }}, "minItems": 4, "maxItems": 4 }},
        \\          "texture_file": {{ "type": "string" }},
        \\          "mesh": {{
        \\            "type": "object",
        \\            "properties": {{
        \\              "vertices": {{ "type": "array" }},
        \\              "indices": {{ "type": "array", "items": {{ "type": "integer" }} }}
        \\            }},
        \\            "required": ["vertices", "indices"]
        \\          }}
        \\        }},
        \\        "required": ["id", "name", "position", "scale", "base_color", "texture_file", "mesh"]
        \\      }}
        \\    }}
        \\  }},
        \\  "required": ["objects"],
        \\  "additionalProperties": true
        \\}}
        \\
    , .{});
}

pub fn worldJsonSchema(allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator,
        \\{{
        \\  "$schema": "https://json-schema.org/draft/2020-12/schema",
        \\  "title": "Friendly Engine World Manifest",
        \\  "type": "object",
        \\  "properties": {{
        \\    "schema_version": {{ "const": 1 }},
        \\    "world_id": {{ "type": "string", "minLength": 1 }},
        \\    "cell_size_m": {{ "type": "number", "exclusiveMinimum": 0 }},
        \\    "cells": {{
        \\      "type": "array",
        \\      "minItems": 1,
        \\      "items": {{
        \\        "type": "object",
        \\        "properties": {{
        \\          "coord": {{
        \\            "type": "array",
        \\            "items": {{ "type": "integer" }},
        \\            "minItems": 2,
        \\            "maxItems": 3
        \\          }},
        \\          "authoring": {{ "type": "string" }},
        \\          "interior_parent": {{
        \\            "type": "array",
        \\            "items": {{ "type": "integer" }},
        \\            "minItems": 2,
        \\            "maxItems": 3
        \\          }}
        \\        }},
        \\        "required": ["coord", "authoring"],
        \\        "additionalProperties": false
        \\      }}
        \\    }}
        \\  }},
        \\  "required": ["schema_version", "cell_size_m", "cells"],
        \\  "additionalProperties": false
        \\}}
        \\
    , .{});
}

pub fn writeSchemaFiles(allocator: std.mem.Allocator, io: std.Io) !void {
    try std.Io.Dir.cwd().createDirPath(io, "docs/schema");

    const scene_schema = try sceneJsonSchema(allocator);
    defer allocator.free(scene_schema);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = "docs/schema/scene.schema.json",
        .data = scene_schema,
    });

    const world_schema = try worldJsonSchema(allocator);
    defer allocator.free(world_schema);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = "docs/schema/world.schema.json",
        .data = world_schema,
    });
}

test "schema writers produce json documents" {
    const scene = try sceneJsonSchema(std.testing.allocator);
    defer std.testing.allocator.free(scene);
    try std.testing.expect(std.mem.indexOf(u8, scene, "next_object_id") != null);

    const world = try worldJsonSchema(std.testing.allocator);
    defer std.testing.allocator.free(world);
    try std.testing.expect(std.mem.indexOf(u8, world, "cell_size_m") != null);
    try std.testing.expect(std.mem.indexOf(u8, world, "\"exclusiveMinimum\": 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, world, "interior_parent") != null);
    try std.testing.expect(std.mem.indexOf(u8, world, "\"additionalProperties\": false") != null);
}
