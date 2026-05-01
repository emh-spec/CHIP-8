const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

/// Display width in pixels, cast to `c_int` for SDL2 compatibility.
const DISPLAY_WIDTH = @as(c_int, @intCast(@import("root.zig").DISPLAY_WIDTH));

/// Display height in pixels, cast to `c_int` for SDL2 compatibility.
const DISPLAY_HEIGHT = @as(c_int, @intCast(@import("root.zig").DISPLAY_HEIGHT));

/// Total number of pixels in the display buffer.
const DISPLAY_SIZE = @as(usize, @intCast(DISPLAY_WIDTH)) * @as(usize, @intCast(DISPLAY_HEIGHT));

/// Display: SDL2-backed window and renderer for the CHIP-8 display.
///
/// Wraps an SDL2 window, renderer, and streaming texture.
/// Converts the emulator's `[bool; 64 * 32]` pixel buffer into
/// ARGB8888 pixels and presents them to the screen each frame.
///
/// # Fields
/// * `window`   - SDL2 window handle
/// * `renderer` - SDL2 renderer attached to the window
/// * `texture`  - Streaming ARGB8888 texture sized 64x32
/// * `pixels`   - Intermediate ARGB8888 pixel buffer uploaded each frame
pub const Display = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    texture: *c.SDL_Texture,
    pixels: [DISPLAY_SIZE]u32,

    /// Initialized Display. create a window, renderer, and texture scaled by `scale`.
    ///
    /// `scale`: pixel scale factor; e.g. 10 gives a 640x320 window.
    ///
    /// Window is created at `64 * scale` x `32 * scale`. Logical size is
    /// set to `64x32` so SDL2 handles scaling automatically.
    /// Uses `errdefer` to clean up partial resources on failure.
    ///
    /// # Error
    ///
    /// Returns error on SDL2 failure.
    pub fn init(scale: c_int) !Display {
        // zig fmt: off
        const window = c.SDL_CreateWindow(
            "CHIP-8 Emulator",
            c.SDL_WINDOWPOS_UNDEFINED,
            c.SDL_WINDOWPOS_UNDEFINED,
            DISPLAY_WIDTH * scale,
            DISPLAY_HEIGHT * scale,
            c.SDL_WINDOW_SHOWN)
        orelse return error.WindowCreationFailed;
        errdefer c.SDL_DestroyWindow(window);

        const renderer = c.SDL_CreateRenderer(window, -1, 0) orelse return error.RendererCreationFailed;
        errdefer c.SDL_DestroyRenderer(renderer);

        _ = c.SDL_RenderSetLogicalSize(renderer, DISPLAY_WIDTH, DISPLAY_HEIGHT);

        const texture = c.SDL_CreateTexture(
            renderer,
            c.SDL_PIXELFORMAT_ARGB8888,
            c.SDL_TEXTUREACCESS_STREAMING,
            DISPLAY_WIDTH,
            DISPLAY_HEIGHT)
        orelse return error.TextureCreationFailed;
        errdefer c.SDL_DestroyTexture(texture);
        
        return Display {
            .window = window,
            .renderer = renderer,
            .texture = texture,
            .pixels = [_]u32{0} ** DISPLAY_SIZE
        };
    }
    // zig fmt: on

    /// Destroy SDL2 resources in reverse creation order.
    ///
    /// Must be called before program exit. Safe to call via `defer`.
    pub fn deinit(self: *Display) void {
        c.SDL_DestroyTexture(self.texture);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
    }

    /// Convert the bool pixel buffer and present it to the screen.
    ///
    /// `display`: slice of 64*32 bools from `Chip8.display`; true = white, false = black.
    ///
    /// Maps each bool to an ARGB8888 value, uploads via `SDL_UpdateTexture`,
    /// clears the renderer, copies the texture, and presents the frame.
    pub fn render(self: *Display, display: []const bool) void {
        for (display, 0..) |on, i| {
            self.pixels[i] = if (on) 0xFFFFFFFF else 0xFF000000;
        }
        _ = c.SDL_UpdateTexture(self.texture, null, &self.pixels, DISPLAY_WIDTH * @sizeOf(u32));
        _ = c.SDL_RenderClear(self.renderer);
        _ = c.SDL_RenderCopy(self.renderer, self.texture, null, null);
        c.SDL_RenderPresent(self.renderer);
    }
};
