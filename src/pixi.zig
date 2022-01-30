const std = @import("std");
const upaya = @import("upaya");
const imgui = @import("imgui");
const sokol = @import("sokol");

pub const editor = @import("editor/editor.zig");

var startup_completed: bool = false;

export fn forward_load_message(path_ptr: [*c]const u8, path_len: c_long) callconv(.C) void {
    const path = path_ptr[0..@intCast(usize, path_len)];
    std.log.debug("forward_load_message: {s}", .{path});

    if (startup_completed) {
        editor.onFileDropped(path);
    } else {
        editor.startup_path = std.fmt.allocPrint(upaya.mem.allocator, "{s}", .{path}) catch unreachable;
    }
    //editor.onFileDropped(path);
}

pub fn main() !void {

    startup_completed = true;

    upaya.run(.{
        .init = editor.init,
        .update = editor.update,
        .shutdown = editor.shutdown,
        .docking = true,
        .docking_flags = imgui.ImGuiDockNodeFlags_NoWindowMenuButton | imgui.ImGuiDockNodeFlags_NoCloseButton,
        .setupDockLayout = editor.setupDockLayout,
        .window_title = "Pixi",
        .onFileDropped = editor.onFileDropped,
        .fullscreen = true, //currently broken on macOS
        .ini_file_storage = .saved_games_dir,
        .app_name = "Pixi",
    });
}
