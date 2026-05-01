const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const Chip8 = @import("chip8").Chip8;
const Display = @import("chip8").Display;
const Input = @import("chip8").Input;

pub fn main(init: std.process.Init) !void {
    const args: []const [:0]const u8 = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        std.debug.print("usage: ./chip8 <path_to_rom>\n", .{});
        return error.NoArgumentGiven;
    }

    const path = args[1];

    // Initializing SDL2.
    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO) < 0) return error.SDLInitFailed;
    defer c.SDL_Quit();

    // Configure SDL2 audio for a mono 44100Hz square wave with 100-sample buffers.
    var spec: c.SDL_AudioSpec = std.mem.zeroes(c.SDL_AudioSpec);
    spec.freq = 44100;
    spec.format = c.AUDIO_S16SYS;
    spec.channels = 1;
    spec.samples = 100;
    spec.callback = audioCallback;

    const dev = c.SDL_OpenAudioDevice(null, 0, &spec, null, 0);
    if (dev == 0) return error.AudioInitFailed;
    defer c.SDL_CloseAudioDevice(dev);

    // Scale factor of 10 gives a 640x320 window from the native 64x32.
    var display = try Display.init(10);
    defer display.deinit();

    var input = Input.init();

    var ch = Chip8.init();
    try ch.load_rom(path, init.arena.allocator(), init.io);

    // Target CPU clock speed in cycles per second.
    const cpu_hz: usize = 700;
    // CPU cycles to run per 60Hz frame.
    const ticks_per_frame = cpu_hz / 60;
    // Target frame duration in milliseconds.
    const ms_per_frame: u32 = 1000 / 60;

    while (true) {
        const frame_start = c.SDL_GetTicks();

        // Poll input first; break if quit signal received.
        if (!input.poll(&ch.keypad)) break;

        // Run CPU ticks for this frame.
        for (0..ticks_per_frame) |_| {
            try ch.tick();
        }

        // Decrement timers, update audio, and render display.
        ch.tick_timers();
        c.SDL_PauseAudioDevice(dev, if (ch.sound_timer > 0) 0 else 1);
        if (ch.draw_flag) {
            display.render(&ch.display);
            ch.draw_flag = false;
        }

        // Sleep remaining frame time to maintain 60Hz.
        const frame_time = c.SDL_GetTicks() - frame_start;
        if (frame_time < ms_per_frame) {
            c.SDL_Delay(ms_per_frame - frame_time);
        }
    }
}

/// SDL2 audio callback; fills `stream` with a square wave.
///
/// `stream`: byte buffer to fill with audio samples.
/// `len`:    length of `stream` in bytes.
///
/// Generates a 16-bit signed square wave at roughly 220Hz by toggling
/// between amplitude `3000` and `-3000` every 100 bytes. Called by SDL2
/// automatically whenever the audio buffer needs refilling.
fn audioCallback(_: ?*anyopaque, stream: [*c]u8, len: c_int) callconv(.c) void {
    const length = @as(usize, @intCast(len));
    var i: usize = 0;
    while (i < length) : (i += 2) {
        const sample: i16 = if ((i / 100) % 2 == 0) 3000 else -3000;
        const bytes: u16 = @bitCast(sample);
        stream[i] = @truncate(bytes);
        stream[i + 1] = @truncate(bytes >> 8);
    }
}
