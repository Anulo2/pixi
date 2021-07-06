const std = @import("std");
const upaya = @import("upaya");
const imgui = @import("imgui");

pub const Camera = @import("../utils/camera.zig").Camera;

const editor = @import("../editor.zig");
const input = @import("../input/input.zig");
const types = @import("../types/types.zig");
const toolbar = editor.toolbar;
const layers = editor.layers;
const sprites = editor.sprites;
const animations = editor.animations;

const File = types.File;
const Layer = types.Layer;
const Animation = types.Animation;

var camera: Camera = .{ .zoom = 2 };
var screen_pos: imgui.ImVec2 = undefined;

var logo: ?upaya.Texture = null;

var active_file_index: usize = 0;
var files: std.ArrayList(File) = undefined;

pub fn init() void {
    files = std.ArrayList(File).init(upaya.mem.allocator);
    var logo_pixels = [_]u32{
        0x00000000, 0xFF89AFEF, 0xFF89AFEF, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0xFF7391D8, 0xFF201a19, 0xFF7391D8, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0xFF5C6DC2, 0xFF5C6DC2, 0xFF5C6DC2, 0xFF89AFEF, 0xFF89AFEF, 0xFF89AFEF, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x8C5058FF, 0xFF201a19, 0xFF201a19, 0xFF201a19, 0xFF7391D8, 0xFF201a19, 0xFF89E6C5, 0x00000000, 0xFF89E6C5, 0x00000000, 0x00000000, 0x00000000,
        0xFF201a19, 0x00000000, 0x00000000, 0xFF5C6DC2, 0xFF5C6DC2, 0xFF5C6DC2, 0xFF201a19, 0xFF7BC167, 0xFF201a19, 0xFFC5E689, 0xFFC5E689, 0xFFC5E689,
        0x00000000, 0x00000000, 0x00000000, 0xFF201a19, 0xFF201a19, 0xFF201a19, 0xFF678540, 0xFF201a19, 0xFF678540, 0xFF201a19, 0xFFA78F4A, 0xFF201a19,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0xFF201a19, 0xFF201a19, 0xFF201a19, 0xFF844531, 0xFF844531, 0xFF844531,
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0xFF201a19, 0xFF201a19, 0xFF201a19,
    };
    logo = upaya.Texture.initWithColorData(&logo_pixels, 12, 8, .nearest, .clamp);
}

pub fn newFile(file: File) void {
    active_file_index = 0;
    files.insert(0, file) catch unreachable;
}

pub fn getNumberOfFiles() usize {
    return files.items.len;
}

pub fn getActiveFile() ?*File {
    if (files.items.len == 0)
        return null;

    if (active_file_index >= files.items.len)
        active_file_index = files.items.len - 1;

    return &files.items[active_file_index];
}

var zoom_time: usize = 0;

pub fn draw() void {
    if (!imgui.igBegin("Canvas", null, imgui.ImGuiWindowFlags_None)) return;
    defer imgui.igEnd();

    // setup screen position and size
    screen_pos = imgui.ogGetCursorScreenPos();
    const window_size = imgui.ogGetContentRegionAvail();
    if (window_size.x == 0 or window_size.y == 0) return;

    if (files.items.len > 0) {
        var texture_position = .{
            .x = -@intToFloat(f32, files.items[active_file_index].background.width) / 2,
            .y = -@intToFloat(f32, files.items[active_file_index].background.height) / 2,
        };

        // draw background texture
        drawTexture(files.items[active_file_index].background, texture_position, 0xFFFFFFFF);

        // draw layers (reverse order)
        var layer_index: usize = files.items[active_file_index].layers.items.len;
        while (layer_index > 0) {
            layer_index -= 1;

            if (files.items[active_file_index].layers.items[layer_index].hidden)
                continue;

            files.items[active_file_index].layers.items[layer_index].updateTexture();
            files.items[active_file_index].layers.items[layer_index].dirty = false;
            drawTexture(files.items[active_file_index].layers.items[layer_index].texture, texture_position, 0xFFFFFFFF);
        }

        // draw tile grid
        drawGrid(files.items[active_file_index], texture_position);

        // draw fill to hide canvas behind transparent tab bar
        var cursor_position = imgui.ogGetCursorPos();
        imgui.ogAddRectFilled(imgui.igGetWindowDrawList(), cursor_position, .{ .x = imgui.ogGetWindowSize().x * 2, .y = 40 }, imgui.ogColorConvertFloat4ToU32(editor.background_color));

        // draw open files tabs
        if (imgui.igBeginTabBar("Canvas Tab Bar", imgui.ImGuiTabBarFlags_Reorderable | imgui.ImGuiTabBarFlags_AutoSelectNewTabs)) {
            defer imgui.igEndTabBar();

            for (files.items) |file, i| {
                var open: bool = true;

                var namePtr = @ptrCast([*c]const u8, file.name);
                if (imgui.igBeginTabItem(namePtr, &open, imgui.ImGuiTabItemFlags_UnsavedDocument)) {
                    defer imgui.igEndTabItem();
                    active_file_index = i;
                }

                if (!open) {
                    // TODO: do i need to deinit all the layers and background?
                    active_file_index = 0;
                    sprites.setActiveSpriteIndex(0);
                    _ = files.swapRemove(i);
                    //f.deinit();
                }
            }
        }
        // store previous tool and reapply it after to allow quick switching
        var previous_tool = toolbar.selected_tool;
        // handle inputs
        if (imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_None) and files.items.len > 0) {
            const io = imgui.igGetIO();
            var mouse_position = io.MousePos;

            //pan
            if (toolbar.selected_tool == .hand and imgui.igIsMouseDragging(imgui.ImGuiMouseButton_Left, 0)) {
                input.pan(&camera, imgui.ImGuiMouseButton_Left);
            }

            if (imgui.igIsMouseDragging(imgui.ImGuiMouseButton_Middle, 0)) {
                input.pan(&camera, imgui.ImGuiMouseButton_Middle);
            }

            if (imgui.igIsMouseDragging(imgui.ImGuiMouseButton_Left, 0) and imgui.ogKeyDown(@intCast(usize, imgui.igGetKeyIndex(imgui.ImGuiKey_Space)))) {
                toolbar.selected_tool = .hand;
                input.pan(&camera, imgui.ImGuiMouseButton_Left);
            }

            // zoom
            if (io.MouseWheel != 0) {
                input.zoom(&camera);
                zoom_time = 20;
            }

            // show tool tip for a few frames after zoom is completed
            if (zoom_time > 0) {
                imgui.igBeginTooltip();
                var zoom_text = std.fmt.allocPrint(upaya.mem.allocator, "{s} {d}x\u{0}", .{ imgui.icons.search, camera.zoom }) catch unreachable;
                imgui.igText(@ptrCast([*c]const u8, zoom_text));
                upaya.mem.allocator.free(zoom_text);
                imgui.igEndTooltip();

                zoom_time -= 1;
            }

            // round positions if we are finished changing cameras position
            if (imgui.igIsMouseReleased(imgui.ImGuiMouseButton_Middle) or imgui.ogKeyUp(@intCast(usize, imgui.igGetKeyIndex(imgui.ImGuiKey_Space)))) {
                camera.position.x = @trunc(camera.position.x);
                camera.position.y = @trunc(camera.position.y);
            }

            if (toolbar.selected_tool == .hand and imgui.igIsMouseReleased(imgui.ImGuiMouseButton_Left)) {
                camera.position.x = @trunc(camera.position.x);
                camera.position.y = @trunc(camera.position.y);
            }

            if (layers.getActiveLayer()) |layer| {
                if (getPixelCoords(layer.texture, texture_position, mouse_position)) |pixel_coords| {
                    var tiles_wide = @divExact(@intCast(usize, files.items[active_file_index].width), @intCast(usize, files.items[active_file_index].tileWidth));

                    var tile_column = @divTrunc(@floatToInt(usize, pixel_coords.x), @intCast(usize, files.items[active_file_index].tileWidth));
                    var tile_row = @divTrunc(@floatToInt(usize, pixel_coords.y), @intCast(usize, files.items[active_file_index].tileHeight));

                    var tile_index = tile_column + tile_row * tiles_wide;
                    var pixel_index = getPixelIndexFromCoords(layer.texture, pixel_coords);

                    // set active sprite window
                    if (io.MouseDown[0] and toolbar.selected_tool != toolbar.Tool.hand and animations.animation_state != .play) {
                        sprites.setActiveSpriteIndex(tile_index);

                        if (toolbar.selected_tool == toolbar.Tool.arrow) {
                            imgui.igBeginTooltip();
                            var index_text = std.fmt.allocPrintZ(upaya.mem.tmp_allocator, "Index: {d}", .{tile_index}) catch unreachable;
                            imgui.igText(@ptrCast([*c]const u8, index_text));
                            imgui.igEndTooltip();
                        }
                    }

                    // color dropper input
                    if (io.MouseDown[1] or ((io.KeyAlt or io.KeySuper) and io.MouseDown[0]) or (io.MouseDown[0] and toolbar.selected_tool == .dropper)) {
                        imgui.igBeginTooltip();
                        var coord_text = std.fmt.allocPrint(upaya.mem.allocator, "{s} {d},{d}\u{0}", .{ imgui.icons.eye_dropper, pixel_coords.x + 1, pixel_coords.y + 1 }) catch unreachable;
                        imgui.igText(@ptrCast([*c]const u8, coord_text));
                        upaya.mem.allocator.free(coord_text);
                        imgui.igEndTooltip();

                        if (layer.image.pixels[pixel_index] == 0x00000000) {
                            if (toolbar.selected_tool != .dropper) {
                                toolbar.selected_tool = .eraser;
                                previous_tool = toolbar.selected_tool;
                            }
                        } else {
                            if (toolbar.selected_tool != .dropper){
                                toolbar.selected_tool = .pencil;
                                previous_tool = toolbar.selected_tool;
                            }
                            
                            toolbar.foreground_color = upaya.math.Color{ .value = layer.image.pixels[pixel_index] };

                            imgui.igBeginTooltip();
                            _ = imgui.ogColoredButtonEx(toolbar.foreground_color.value, "###1", .{ .x = 100, .y = 100 });
                            imgui.igEndTooltip();
                        }
                    }

                    // drawing input
                    if (toolbar.selected_tool == .pencil or toolbar.selected_tool == .eraser) {
                        if (imgui.igIsMouseDragging(imgui.ImGuiMouseButton_Left, 0))
                            layer.image.pixels[pixel_index] = if (toolbar.selected_tool == .pencil) toolbar.foreground_color.value else 0x00000000;
                        layer.dirty = true;
                    }

                    if (toolbar.selected_tool == .animation) {
                        if (io.MouseClicked[0] and !imgui.ogKeyDown(upaya.sokol.SAPP_KEYCODE_SPACE)) {
                            if (animations.getActiveAnimation()) |animation| {
                                animation.start = tile_index;
                            }
                        }

                        if (imgui.igIsMouseDragging(imgui.ImGuiMouseButton_Left, 0)) {
                            if (animations.getActiveAnimation()) |animation| {
                                if (@intCast(i32, tile_index) - @intCast(i32, animation.start) + 1 >= 0)
                                    animation.length = tile_index - animation.start + 1;
                            }
                        }
                    }
                }
            }

            toolbar.selected_tool = previous_tool;
        }
    } else {
        camera.position = .{ .x = 0, .y = 0 };
        camera.zoom = 28;

        var logo_pos = .{ .x = -@intToFloat(f32, logo.?.width) / 2, .y = -@intToFloat(f32, logo.?.height) / 2 };
        // draw background texture
        drawTexture(logo.?, logo_pos, 0x33FFFFFF);

        var text_pos = imgui.ogGetWindowCenter();
        text_pos.y += @intToFloat(f32, logo.?.height);
        text_pos.y += 175;
        text_pos.x -= 60;

        imgui.ogSetCursorPos(text_pos);
        imgui.ogColoredText(0.3, 0.3, 0.3, "New File " ++ imgui.icons.file ++ " (cmd + n)");
    }
}

fn drawGrid(file: File, position: imgui.ImVec2) void {
    var tilesWide = @divExact(file.width, file.tileWidth);
    var tilesTall = @divExact(file.height, file.tileHeight);

    var x: i32 = 0;
    while (x <= tilesWide) : (x += 1) {
        var top = position.add(.{ .x = @intToFloat(f32, x * file.tileWidth), .y = 0 });
        var bottom = position.add(.{ .x = @intToFloat(f32, x * file.tileWidth), .y = @intToFloat(f32, file.height) });

        top = camera.matrix().transformImVec2(top).add(screen_pos);
        bottom = camera.matrix().transformImVec2(bottom).add(screen_pos);

        imgui.ogImDrawList_AddLine(imgui.igGetWindowDrawList(), top, bottom, editor.gridColor.value, 1);
    }

    var y: i32 = 0;
    while (y <= tilesTall) : (y += 1) {
        var left = position.add(.{ .x = 0, .y = @intToFloat(f32, y * file.tileHeight) });
        var right = position.add(.{ .x = @intToFloat(f32, file.width), .y = @intToFloat(f32, y * file.tileHeight) });

        left = camera.matrix().transformImVec2(left).add(screen_pos);
        right = camera.matrix().transformImVec2(right).add(screen_pos);

        imgui.ogImDrawList_AddLine(imgui.igGetWindowDrawList(), left, right, editor.gridColor.value, 1);
    }

    if (sprites.getActiveSprite()) |sprite| {
        var column = @mod(@intCast(i32, sprite.index), tilesWide);
        var row = @divTrunc(@intCast(i32, sprite.index), tilesWide);

        var tl: imgui.ImVec2 = position.add(.{ .x = @intToFloat(f32, column * file.tileWidth), .y = @intToFloat(f32, row * file.tileHeight) });
        tl = camera.matrix().transformImVec2(tl).add(screen_pos);
        var size: imgui.ImVec2 = .{ .x = @intToFloat(f32, file.tileWidth), .y = @intToFloat(f32, file.tileHeight) };
        size = size.scale(camera.zoom);

        imgui.ogAddRect(imgui.igGetWindowDrawList(), tl, size, imgui.ogColorConvertFloat4ToU32(editor.highlight_color_green), 2);
    }

    if (animations.getActiveAnimation()) |animation| {
        const start_column = @mod(@intCast(i32, animation.start), tilesWide);
        const start_row = @divTrunc(@intCast(i32, animation.start), tilesWide);

        var start_tl: imgui.ImVec2 = position.add(.{ .x = @intToFloat(f32, start_column * file.tileWidth), .y = @intToFloat(f32, start_row * file.tileHeight) });
        var start_bl: imgui.ImVec2 = start_tl.add(.{ .x = 0, .y = @intToFloat(f32, file.tileHeight) });
        var start_tm: imgui.ImVec2 = start_tl.add(.{ .x = @intToFloat(f32, @divTrunc(file.tileWidth, 2)) });
        var start_bm: imgui.ImVec2 = start_bl.add(.{ .x = @intToFloat(f32, @divTrunc(file.tileWidth, 2)) });
        start_tl = camera.matrix().transformImVec2(start_tl).add(screen_pos);
        start_bl = camera.matrix().transformImVec2(start_bl).add(screen_pos);

        start_tm = camera.matrix().transformImVec2(start_tm).add(screen_pos);
        start_bm = camera.matrix().transformImVec2(start_bm).add(screen_pos);
        imgui.ogImDrawList_AddLine(imgui.igGetWindowDrawList(), start_tl, start_bl, 0xFFFFAA00, 2);
        imgui.ogImDrawList_AddLine(imgui.igGetWindowDrawList(), start_tl, start_tm, 0xFFFFAA00, 2);
        imgui.ogImDrawList_AddLine(imgui.igGetWindowDrawList(), start_bl, start_bm, 0xFFFFAA00, 2);

        const end_column = @mod(@intCast(i32, animation.start + animation.length - 1), tilesWide);
        const end_row = @divTrunc(@intCast(i32, animation.start + animation.length - 1), tilesWide);

        var end_tr: imgui.ImVec2 = position.add(.{ .x = @intToFloat(f32, end_column * file.tileWidth + file.tileWidth), .y = @intToFloat(f32, end_row * file.tileHeight) });
        var end_br: imgui.ImVec2 = end_tr.add(.{ .x = 0, .y = @intToFloat(f32, file.tileHeight) });
        var end_tm: imgui.ImVec2 = end_tr.subtract(.{ .x = @intToFloat(f32, @divTrunc(file.tileWidth, 2)) });
        var end_bm: imgui.ImVec2 = end_br.subtract(.{ .x = @intToFloat(f32, @divTrunc(file.tileWidth, 2)) });
        end_tr = camera.matrix().transformImVec2(end_tr).add(screen_pos);
        end_br = camera.matrix().transformImVec2(end_br).add(screen_pos);

        end_tm = camera.matrix().transformImVec2(end_tm).add(screen_pos);
        end_bm = camera.matrix().transformImVec2(end_bm).add(screen_pos);
        imgui.ogImDrawList_AddLine(imgui.igGetWindowDrawList(), end_tr, end_br, 0xFFAA00FF, 2);
        imgui.ogImDrawList_AddLine(imgui.igGetWindowDrawList(), end_tr, end_tm, 0xFFAA00FF, 2);
        imgui.ogImDrawList_AddLine(imgui.igGetWindowDrawList(), end_br, end_bm, 0xFFAA00FF, 2);
    }
}

fn drawTexture(texture: upaya.Texture, position: imgui.ImVec2, color: u32) void {
    const tl = camera.matrix().transformImVec2(position).add(screen_pos);
    var br = position;
    br.x += @intToFloat(f32, texture.width);
    br.y += @intToFloat(f32, texture.height);
    br = camera.matrix().transformImVec2(br).add(screen_pos);

    imgui.ogImDrawList_AddImage(
        imgui.igGetWindowDrawList(),
        texture.imTextureID(),
        tl,
        br,
        .{},
        .{ .x = 1, .y = 1 },
        color,
    );
}

fn getPixelCoords(texture: upaya.Texture, texture_position: imgui.ImVec2, position: imgui.ImVec2) ?imgui.ImVec2 {
    var tl = camera.matrix().transformImVec2(texture_position).add(screen_pos);
    var br: imgui.ImVec2 = texture_position;
    br.x += @intToFloat(f32, texture.width);
    br.y += @intToFloat(f32, texture.height);
    br = camera.matrix().transformImVec2(br).add(screen_pos);

    if (position.x > tl.x and position.x < br.x and position.y < br.y and position.y > tl.y) {
        var pixel_pos: imgui.ImVec2 = .{};

        pixel_pos.x = @divTrunc(position.x - tl.x, camera.zoom);
        pixel_pos.y = @divTrunc(position.y - tl.y, camera.zoom);

        return pixel_pos;
    } else return null;
}

// fn getTileIndexFromCoords( file: File, coords: imgui.ImVec2) usize {
//    var column = @divTrunc(@floatToInt(usize, coords.x), @intCast(usize, file.tileWidth));
//    var row = @divTrunc(@floatToInt(usize, coords.y), @intCast(usize, file.tileHeight));

//    return column + row * @intCast(usize, @divTrunc(file.width, file.tileWidth));

// }

fn getPixelIndexFromCoords(texture: upaya.Texture, coords: imgui.ImVec2) usize {
    return @floatToInt(usize, coords.x + coords.y * @intToFloat(f32, texture.width));
}

// helper for getting texture pixel index from screen position
fn getPixelIndex(texture: upaya.Texture, texture_position: imgui.ImVec2, position: imgui.ImVec2) ?usize {
    if (getPixelCoords(texture, texture_position, position)) |coords| {
        return getPixelIndexFromCoords(texture, coords);
    } else return null;
}

pub fn close() void {
    logo.?.deinit();
    for (files.items) |_, i| {
        files.items[i].deinit();
    }
}
