const std = @import("std");

const core = @import("core");
const gpu = core.gpu;

const zgui = @import("zgui").MachImgui(core);
const zstbi = @import("zstbi");
const zm = @import("zmath");
const nfd = @import("nfd");

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

timer: core.Timer,

pub const name: [:0]const u8 = "Pixi";
pub const version: []const u8 = "0.0.1";
pub const Settings = @import("settings.zig");
pub const Popups = @import("editor/popups/Popups.zig");
pub const Packer = @import("tools/Packer.zig");

pub const editor = @import("editor/editor.zig");

pub const assets = @import("assets.zig");
pub const shaders = @import("shaders.zig");

pub const fs = @import("tools/fs.zig");
pub const fa = @import("tools/font_awesome.zig");
pub const math = @import("math/math.zig");
pub const gfx = @import("gfx/gfx.zig");
pub const input = @import("input/input.zig");
pub const storage = @import("storage/storage.zig");

pub const algorithms = @import("algorithms/algorithms.zig");

test {
    _ = zstbi;
    _ = math;
    _ = gfx;
    _ = input;
}

pub var application: *App = undefined;
pub var state: *PixiState = undefined;
pub var content_scale: [2]f32 = undefined;
pub var window_size: [2]f32 = undefined;
pub var framebuffer_size: [2]f32 = undefined;

pub const Colors = @import("Colors.zig");
pub const Cursors = @import("Cursors.zig");
pub const Recents = @import("Recents.zig");
pub const Tools = @import("Tools.zig");

/// Holds the global game state.
pub const PixiState = struct {
    allocator: std.mem.Allocator = undefined,
    settings: Settings = .{},
    hotkeys: input.Hotkeys,
    mouse: input.Mouse,
    sidebar: Sidebar = .files,
    theme: editor.Theme = .{},
    project_folder: ?[:0]const u8 = null,
    recents: Recents,
    previous_atlas_export: ?[:0]const u8 = null,
    background_logo: gfx.Texture,
    fox_logo: gfx.Texture,
    open_files: std.ArrayList(storage.Internal.Pixi),
    pack_target: PackTarget = .project,
    pack_camera: gfx.Camera = .{},
    packer: Packer,
    atlas: storage.Internal.Atlas = .{},
    open_file_index: usize = 0,
    tools: Tools = .{},
    popups: Popups = .{},
    should_close: bool = false,
    fonts: Fonts = .{},
    cursors: Cursors,
    colors: Colors,
    delta_time: f32 = 0.0,
};

pub const Sidebar = enum {
    files,
    tools,
    layers,
    sprites,
    animations,
    pack,
    settings,
};

pub const Fonts = struct {
    fa_standard_regular: zgui.Font = undefined,
    fa_standard_solid: zgui.Font = undefined,
    fa_small_regular: zgui.Font = undefined,
    fa_small_solid: zgui.Font = undefined,
};

pub const PackTarget = enum {
    project,
    all_open,
    single_open,
};

pub fn init(app: *App) !void {
    try core.init(.{
        .title = name,
        .size = .{ .width = 1400, .height = 800 },
    });
    application = app;

    const descriptor = core.descriptor;
    window_size = .{ @floatFromInt(core.size().width), @floatFromInt(core.size().height) };
    framebuffer_size = .{ @floatFromInt(descriptor.width), @floatFromInt(descriptor.height) };
    content_scale = .{
        // type inference doesn't like this, but the important part is to make sure we're dividing
        // as floats not integers.
        framebuffer_size[0] / window_size[0],
        framebuffer_size[1] / window_size[1],
    };

    const scale_factor = content_scale[1];

    const allocator = gpa.allocator();

    zstbi.init(allocator);

    var open_files = std.ArrayList(storage.Internal.Pixi).init(allocator);

    // Logos
    const background_logo = try gfx.Texture.loadFromFile(assets.icon1024_png.path, .{});
    const fox_logo = try gfx.Texture.loadFromFile(assets.fox1024_png.path, .{});

    // Cursors
    const pencil = try gfx.Texture.loadFromFile(if (scale_factor > 1) assets.pencil64_png.path else assets.pencil32_png.path, .{});
    const eraser = try gfx.Texture.loadFromFile(if (scale_factor > 1) assets.eraser64_png.path else assets.eraser32_png.path, .{});

    const hotkeys = try input.Hotkeys.initDefault(allocator);
    const mouse = try input.Mouse.initDefault(allocator);

    const packer = try Packer.init(allocator);
    const recents = try Recents.init(allocator);

    state = try gpa.allocator().create(PixiState);

    state.* = .{
        .allocator = allocator,
        .background_logo = background_logo,
        .fox_logo = fox_logo,
        .open_files = open_files,
        .cursors = .{
            .pencil = pencil,
            .eraser = eraser,
        },
        .colors = try Colors.load(),
        .hotkeys = hotkeys,
        .mouse = mouse,
        .packer = packer,
        .recents = recents,
    };

    app.* = .{
        .timer = try core.Timer.start(),
    };

    zgui.init(allocator);
    zgui.mach_backend.init(core.device, core.descriptor.format, .{});
    zgui.io.setIniFilename("imgui.ini");
    _ = zgui.io.addFontFromFile(assets.root ++ "fonts/CozetteVector.ttf", state.settings.font_size * scale_factor);
    var config = zgui.FontConfig.init();
    config.merge_mode = true;
    const ranges: []const u16 = &.{ 0xf000, 0xf976, 0 };
    state.fonts.fa_standard_solid = zgui.io.addFontFromFileWithConfig(assets.root ++ "fonts/fa-solid-900.ttf", state.settings.font_size * scale_factor, config, ranges.ptr);
    state.fonts.fa_standard_regular = zgui.io.addFontFromFileWithConfig(assets.root ++ "fonts/fa-regular-400.ttf", state.settings.font_size * scale_factor, config, ranges.ptr);
    state.fonts.fa_small_solid = zgui.io.addFontFromFileWithConfig(assets.root ++ "fonts/fa-solid-900.ttf", 10 * scale_factor, config, ranges.ptr);
    state.fonts.fa_small_regular = zgui.io.addFontFromFileWithConfig(assets.root ++ "fonts/fa-regular-400.ttf", 10 * scale_factor, config, ranges.ptr);
    state.theme.init();
}

pub fn updateMainThread(_: *App) !bool {
    if (state.popups.file_dialog_request) |request| {
        const initial = if (request.initial) |initial| initial else state.project_folder;

        if (switch (request.state) {
            .file => try nfd.openFileDialog(request.filter, initial),
            .folder => try nfd.openFolderDialog(initial),
            .save => try nfd.saveFileDialog(request.filter, initial),
        }) |path| {
            state.popups.file_dialog_response = .{
                .path = path,
                .type = request.type,
            };
        }
        state.popups.file_dialog_request = null;
    }

    return false;
}

pub fn update(app: *App) !bool {
    zgui.mach_backend.newFrame();
    state.delta_time = app.timer.lap();
    const descriptor = core.descriptor;
    window_size = .{ @floatFromInt(core.size().width), @floatFromInt(core.size().height) };
    framebuffer_size = .{ @floatFromInt(descriptor.width), @floatFromInt(descriptor.height) };
    content_scale = .{
        // type inference doesn't like this, but the important part is to make sure we're dividing
        // as floats not integers.
        framebuffer_size[0] / window_size[0],
        framebuffer_size[1] / window_size[1],
    };

    var iter = core.pollEvents();
    while (iter.next()) |event| {
        state.cursors.current = .arrow;
        switch (event) {
            .key_press => |key_press| {
                state.hotkeys.setHotkeyState(key_press.key, key_press.mods, .press);
            },
            .key_repeat => |key_repeat| {
                state.hotkeys.setHotkeyState(key_repeat.key, key_repeat.mods, .repeat);
            },
            .key_release => |key_release| {
                state.hotkeys.setHotkeyState(key_release.key, key_release.mods, .release);
            },
            .mouse_scroll => |mouse_scroll| {
                state.mouse.scroll_x = mouse_scroll.xoffset;
                state.mouse.scroll_y = mouse_scroll.yoffset;
            },
            .mouse_motion => |mouse_motion| {
                state.mouse.position = .{ @floatCast(mouse_motion.pos.x * content_scale[0]), @floatCast(mouse_motion.pos.y * content_scale[1]) };
            },
            .mouse_press => |mouse_press| {
                state.mouse.setButtonState(mouse_press.button, mouse_press.mods, .press);
            },
            .mouse_release => |mouse_release| {
                state.mouse.setButtonState(mouse_release.button, mouse_release.mods, .release);
            },
            .close => {
                var should_close = true;
                for (state.open_files.items) |file| {
                    if (file.dirty()) {
                        should_close = false;
                    }
                }

                if (!should_close and !state.popups.file_confirm_close_exit) {
                    state.popups.file_confirm_close = true;
                    state.popups.file_confirm_close_state = .all;
                    state.popups.file_confirm_close_exit = true;
                }
                state.should_close = should_close;
            },
            else => {},
        }
        zgui.mach_backend.passEvent(event, content_scale);
    }

    try input.process();

    state.theme.set();
    editor.draw();
    state.theme.unset();
    state.cursors.update();

    if (core.swap_chain.getCurrentTextureView()) |back_buffer_view| {
        defer back_buffer_view.release();

        const zgui_commands = commands: {
            const encoder = core.device.createCommandEncoder(null);
            defer encoder.release();

            const background: gpu.Color = .{
                .r = @floatCast(state.theme.foreground.value[0]),
                .g = @floatCast(state.theme.foreground.value[1]),
                .b = @floatCast(state.theme.foreground.value[2]),
                .a = 1.0,
            };

            // Gui pass.
            {
                const color_attachment = gpu.RenderPassColorAttachment{
                    .view = back_buffer_view,
                    .clear_value = background,
                    .load_op = .clear,
                    .store_op = .store,
                };

                const render_pass_info = gpu.RenderPassDescriptor.init(.{
                    .color_attachments = &.{color_attachment},
                });
                const pass = encoder.beginRenderPass(&render_pass_info);

                zgui.mach_backend.draw(pass);
                pass.end();
                pass.release();
            }

            break :commands encoder.finish(null);
        };
        defer zgui_commands.release();

        core.queue.submit(&.{zgui_commands});
        core.swap_chain.present();
    }

    for (state.hotkeys.hotkeys) |*hotkey| {
        hotkey.previous_state = hotkey.state;
    }

    for (state.mouse.buttons) |*button| {
        button.previous_state = button.state;
    }

    state.mouse.previous_position = state.mouse.position;

    if (state.should_close and !editor.saving())
        return true;

    return false;
}

pub fn deinit(_: *App) void {
    state.allocator.free(state.hotkeys.hotkeys);
    state.background_logo.deinit();
    state.fox_logo.deinit();
    state.cursors.deinit();
    state.colors.deinit();
    state.packer.deinit();
    state.recents.deinit();
    if (state.atlas.external) |*atlas| {
        for (atlas.sprites) |sprite| {
            state.allocator.free(sprite.name);
        }

        for (atlas.animations) |animation| {
            state.allocator.free(animation.name);
        }

        state.allocator.free(atlas.sprites);
        state.allocator.free(atlas.animations);
    }
    if (state.previous_atlas_export) |path| {
        state.allocator.free(path);
    }
    if (state.atlas.diffusemap) |*diffusemap| diffusemap.deinit();
    if (state.atlas.heightmap) |*heightmap| heightmap.deinit();
    editor.deinit();
    zgui.mach_backend.deinit();
    zgui.deinit();
    zstbi.deinit();
    state.allocator.destroy(state);
    core.deinit();
}
