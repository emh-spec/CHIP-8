const std = @import("std");

const DIS_W = @import("root.zig").DISPLAY_WIDTH;
const DIS_H = @import("root.zig").DISPLAY_HEIGHT;

/// All the error type that can happen in CHIP-8.
pub const Chip8Error = error{
    /// The `opcode` is either unknown or invalid.
    InvalidOpcode,

    /// If the stack is empty and some operations tries to `pop` it.
    StackUnderflow,

    /// If the stack pointer exceeds the stack bound.
    StackOverflow,

    /// When the ROM exceeds available memory.
    MemoryOverflow,

    /// The rom buffer is empty.
    EmptyBuffer,
};

/// Built-in font set of the emulator, with sprite data representing
/// the hexadecimal numbers from `0` through `F`.
/// Each font character should be 4 pixels wide by 5 pixels tall.
const FONT_SET = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

/// Program starting address.
const PROGRAM_STR_ADD: u16 = 0x200;

/// Font set starting address in memory.
const FONT_STR_ADD: usize = 0x00;

/// Memory size.
const MEM_SIZE: usize = 0x1000;

/// Total display size.
const DISPLAY_SIZE: usize = DIS_W * DIS_H;

/// A random number generator.
var prng = std.Random.DefaultPrng.init(12345);

/// CHIP-8: contain all the internals and methods of the emulator.
pub const Chip8 = struct {
    /// 4KB ram.
    memory: [MEM_SIZE]u8,

    /// 16 8-bit (one byte) general-purpose variable registers, ie. 0
    /// through 15 in decimal, called `V0` through `VF`.
    ///
    /// * VF is also used as a flag register; many instructions will set it to either 1 or 0 based
    /// on some rule, for example using it as a carry flag.
    v_regs: [16]u8,

    /// 16-bit index register used to store memory addresses.
    i_reg: u16,

    /// Program counter.
    /// Points at the current instruction in memory.
    pc: u16,

    /// Stack pointer. Points to the top of the stack.
    sp: u8,

    /// 16-level call stack. Stores return addresses for subroutine calls.
    stack: [16]u16,

    /// An 8-bit delay timer which is decremented at a rate of 60 Hz (60 times per second) until it reaches `0`.
    delay_timer: u8,

    /// An 8-bit sound timer which functions like the delay timer,
    /// but which also gives off a beeping sound as long as it’s not `0`.
    sound_timer: u8,

    /// 64 x 32 pixels monochrome display buffer.
    display: [DISPLAY_SIZE]bool,

    /// State of the 16-key hexadecimal keypad (0-F).
    keypad: [16]bool,

    /// Flag indicator. Check if the CPU is halted & waiting for a key press.
    waiting_for_key: bool,

    /// Register index (V0-VF) where the detected key value will be stored.
    waiting_reg: usize,

    /// Returns a new CHIP-8 instance.
    ///
    /// Constructs a fresh CHIP-8 instance with zeroed memory and registers.
    /// Loads the built-in font set into memory at address `0x000`.
    ///
    /// # Examples
    ///
    /// ```zig
    /// const ch = Chip8.init();
    /// ```
    pub fn init() Chip8 {
        var ch = Chip8{
            .memory = [_]u8{0} ** MEM_SIZE,
            .v_regs = [_]u8{0} ** 16,
            .i_reg = 0,
            .pc = PROGRAM_STR_ADD,
            .sp = 0,
            .stack = [_]u16{0} ** 16,
            .delay_timer = 0,
            .sound_timer = 0,
            .display = [_]bool{false} ** DISPLAY_SIZE,
            .keypad = [_]bool{false} ** 16,
            .waiting_for_key = false,
            .waiting_reg = 0,
        };

        // Loads the font set at the start of memory.
        @memcpy(ch.memory[FONT_STR_ADD .. FONT_STR_ADD + FONT_SET.len], &FONT_SET);

        return ch;
    }

    /// Loads `src` ROM data into memory address 0x200.
    ///
    /// # Errors
    ///
    /// Returns `MemoryOverflow` if the `src` len is greater than available
    /// memory (`4096 - 512 = 3584`).
    ///
    /// # Examples
    ///
    /// ```zig
    /// var ch = Chip8.init();
    ///
    /// const rom = try std.fs.cwd().readFileAlloc(allocator, "roms/pong.ch8", .unlimited);
    /// defer allocator.free(rom);
    /// try ch.load_rom(rom);
    /// ```
    pub fn load_rom(self: *Chip8, src: []const u8) Chip8Error!void {
        const start = @as(usize, PROGRAM_STR_ADD);

        if ((MEM_SIZE - start) < src.len) return error.MemoryOverflow;

        @memcpy(self.memory[start .. start + src.len], src);
    }

    /// Decrements the delay and sound timers by 1.
    /// Should be called at 60 Hz.
    pub fn tick_timers(self: *Chip8) void {
        if (self.delay_timer > 0) self.delay_timer -= 1;
        if (self.sound_timer > 0) self.sound_timer -= 1;
    }

    /// Executes a single CPU cycle: fetch, decode, and execute.
    ///
    /// Also checks if `waiting_for_key` is true, the CPU halts until a key is pressed.
    ///
    /// # Errors
    ///
    /// Returns the same errors as `execute()`: `InvalidOpcode`, `StackOverflow`, `StackUnderflow`.
    ///
    /// # Examples
    ///
    /// ```zig
    /// var ch = Chip8.init();
    ///
    /// try ch.tick();
    /// ```
    pub fn tick(self: *Chip8) Chip8Error!void {
        if (self.waiting_for_key) {
            for (0..16) |i| {
                if (self.keypad[i]) {
                    self.v_regs[self.waiting_reg] = @intCast(i);
                    self.waiting_for_key = false;
                    break;
                }
            }
            return;
        }

        const opcode = self.fetch();
        try self.execute(opcode);
    }

    /// Fetches the next 16-bit opcode from memory and increments the program counter (`pc`).
    ///
    /// # Examples
    ///
    /// ```zig
    /// var ch = Chip8.init();
    ///
    /// const opcode = ch.fetch();
    /// ```
    pub fn fetch(self: *Chip8) u16 {
        const high_byte = self.memory[self.pc];
        const low_byte = self.memory[self.pc + 1];
        const opcode = (@as(u16, high_byte) << 8) | low_byte;

        self.pc += 2;
        return opcode;
    }

    /// Decodes the `opcode` and executes it.
    ///
    /// # Errors
    ///
    /// Returns `StackUnderflow` when the stack pointer (`sp`) is equal to `0`.
    ///
    /// Returns `StackOverflow` when the stack pointer (`sp`) is greater or equal to `16`.
    ///
    /// Returns `InvalidOpcode` when the decoded `opcode` is unknown or invalid.
    ///
    /// # Examples
    ///
    /// ```zig
    /// var ch = Chip8.init();
    ///
    /// var opcode = ch.fetch();
    /// try ch.execute(opcode);
    /// ```
    pub fn execute(self: *Chip8, opcode: u16) Chip8Error!void {}
};
