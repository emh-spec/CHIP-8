const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

// zig fmt: off


/// Input: maps SDL2 keyboard events to the CHIP-8 16-key hex keypad.
///
/// The keymap translates physical keyboard keys to CHIP-8 keypad indices
/// using the standard layout:
///
/// ```
/// CHIP-8    Keyboard
/// 1 2 3 4   1 2 3 4
/// 5 6 7 8   Q W E R
/// 9 A B C   A S D F
/// D E F 0   Z X C V
/// ```
///
/// # Fields
/// * `keymap` - array of 16 SDL keycodes, indexed by CHIP-8 key (0x0..=0xF)
pub const Input = struct {
    keymap: [16]c_int,
    
    /// Construct an `Input` with the standard keyboard layout.
    ///
    /// # Return
    /// 
    /// `Input` instance with keymap pre-filled.
    pub fn init() Input {
        return Input{
            .keymap = [16]c_int{
                c.SDLK_1, c.SDLK_2, c.SDLK_3, c.SDLK_4,
                c.SDLK_q, c.SDLK_w, c.SDLK_e, c.SDLK_r,
                c.SDLK_a, c.SDLK_s, c.SDLK_d, c.SDLK_f,
                c.SDLK_z, c.SDLK_x, c.SDLK_c, c.SDLK_v,
            }
        };
    }
// zig fmt: on

    /// Drain the SDL2 event queue and update keypad state.
    ///
    /// `keypad`: mutable reference to `Chip8.keypad`; updated on key press/release.
    ///
    /// Processes all pending SDL events. On `SDL_KEYDOWN`, sets the matching
    /// keypad entry to `true`. On `SDL_KEYUP`, sets it to `false`.
    /// `Escape` and `SDL_QUIT` both signal the emulator to stop.
    ///
    /// # Return
    ///
    /// `true` to continue running, `false` to quit.
    pub fn poll(self: *Input, keypad: *[16]bool) bool {
        var event: c.SDL_Event = undefined;

        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => return false,
                c.SDL_KEYDOWN => {
                    if (event.key.keysym.sym == c.SDLK_ESCAPE) return false;
                    for (self.keymap, 0..) |k, i| {
                        if (event.key.keysym.sym == k) keypad[i] = true;
                    }
                },
                c.SDL_KEYUP => {
                    for (self.keymap, 0..) |k, i| {
                        if (event.key.keysym.sym == k) keypad[i] = false;
                    }
                },
                else => {},
            }
        }
        return true;
    }
};
