//! A link is a clickable element that can be used to trigger some action.
//! A link is NOT just a URL that opens in a browser. A link is any generic
//! regular expression match over terminal text that can trigger various
//! action types.
const Link = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const oni = @import("oniguruma");
const Mods = @import("key.zig").Mods;

/// The regular expression that will be used to match the link. Ownership
/// of this memory is up to the caller. The link will never free this memory.
regex: []const u8,

/// The action that will be triggered when the link is clicked.
action: Action,

/// The situations in which the link will be highlighted. A link is only
/// clickable by the mouse when it is highlighted, so this also controls
/// when the link is clickable.
highlight: Highlight,

pub const Action = union(enum) {
    /// Open the full matched value using the default open program.
    /// For example, on macOS this is "open" and on Linux this is "xdg-open".
    open: void,

    /// Open the OSC8 hyperlink under the mouse position. _-prefixed means
    /// this can't be user-specified, it's only used internally.
    _open_osc8: void,
};

pub const Highlight = union(enum) {
    /// Always highlight the link.
    always: void,

    /// Only highlight the link when the mouse is hovering over it.
    hover: void,

    /// Highlight anytime the given mods are pressed, either when
    /// hovering or always. For always, all links will be highlighted
    /// when the mods are pressed regardless of if the mouse is hovering
    /// over them.
    ///
    /// Note that if "shift" is specified here, this will NEVER match in
    /// TUI programs that capture mouse events. "Shift" with mouse capture
    /// escapes the mouse capture but strips the "shift" so it can't be
    /// detected.
    always_mods: Mods,
    hover_mods: Mods,
};

pub const FilePath = struct {
    path: []const u8,
    line: ?[]const u8 = null,
    column: ?[]const u8 = null,
};

/// Split up to two trailing numeric `:line[:column]` segments from a path.
pub fn parseFilePath(value: []const u8) FilePath {
    var result: FilePath = .{ .path = value };

    for (0..2) |_| {
        const separator = std.mem.lastIndexOfScalar(u8, result.path, ':') orelse break;
        const segment = result.path[separator + 1 ..];
        if (!allDigits(segment)) break;

        result.column = result.line;
        result.line = segment;
        result.path = result.path[0..separator];
    }

    return result;
}

fn allDigits(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |char| if (!std.ascii.isDigit(char)) return false;
    return true;
}

/// Returns a new oni.Regex that can be used to match the link.
pub fn oniRegex(self: *const Link) !oni.Regex {
    return try oni.Regex.init(
        self.regex,
        .{},
        oni.Encoding.utf8,
        oni.Syntax.default,
        null,
    );
}

/// Deep clone the link.
pub fn clone(self: *const Link, alloc: Allocator) Allocator.Error!Link {
    return .{
        .regex = try alloc.dupe(u8, self.regex),
        .action = self.action,
        .highlight = self.highlight,
    };
}

/// Check if two links are equal.
pub fn equal(self: *const Link, other: *const Link) bool {
    return std.meta.eql(self.action, other.action) and
        std.meta.eql(self.highlight, other.highlight) and
        std.mem.eql(u8, self.regex, other.regex);
}

test "parse file path location" {
    const testing = std.testing;

    {
        const parsed = parseFilePath("/tmp/main.zig");
        try testing.expectEqualStrings("/tmp/main.zig", parsed.path);
        try testing.expect(parsed.line == null);
        try testing.expect(parsed.column == null);
    }
    {
        const parsed = parseFilePath("/tmp/main.zig:42");
        try testing.expectEqualStrings("/tmp/main.zig", parsed.path);
        try testing.expectEqualStrings("42", parsed.line.?);
        try testing.expect(parsed.column == null);
    }
    {
        const parsed = parseFilePath("/tmp/main.zig:42:10");
        try testing.expectEqualStrings("/tmp/main.zig", parsed.path);
        try testing.expectEqualStrings("42", parsed.line.?);
        try testing.expectEqualStrings("10", parsed.column.?);
    }
    {
        const parsed = parseFilePath("/tmp/name:with:colon:42:10");
        try testing.expectEqualStrings("/tmp/name:with:colon", parsed.path);
        try testing.expectEqualStrings("42", parsed.line.?);
        try testing.expectEqualStrings("10", parsed.column.?);
    }
    {
        const parsed = parseFilePath("/tmp/main.zig:line");
        try testing.expectEqualStrings("/tmp/main.zig:line", parsed.path);
        try testing.expect(parsed.line == null);
        try testing.expect(parsed.column == null);
    }
    {
        const parsed = parseFilePath("/tmp/main.zig:42:column");
        try testing.expectEqualStrings("/tmp/main.zig:42:column", parsed.path);
        try testing.expect(parsed.line == null);
        try testing.expect(parsed.column == null);
    }
}
