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
    pub fn execute(self: *Chip8, opcode: u16) Chip8Error!void {
        // The first nibble. Store the instruction types.
        const op = @as(u4, @truncate((opcode & 0xF000) >> 12));
        // The second nibble. Vx register index.
        const x = @as(u4, @truncate((opcode & 0x0F00) >> 8));
        // The third nibble. Vy register index.
        const y = @as(u4, @truncate((opcode & 0x00F0) >> 4));
        // The fourth nibble. A 4-bit number.
        const n = @as(u4, @truncate(opcode));

        // The second byte (third and fourth nibbles). An 8-bit immediate number.
        const nn = @as(u8, @truncate(opcode));
        // The second, third and fourth nibbles. A 12-bit immediate memory address.
        const nnn = @as(u12, @truncate(opcode));

        switch (op) {
            // 0x0 - CLS / RET: dispatch on nn to differentiate 00E0 and 00EE.
            0x0 => switch (nn) {
                // 00E0 - CLS: clear the display buffer.
                0xE0 => self.display = [_]bool{false} ** DISPLAY_SIZE,
                // 00EE - RET: pop return address from stack and resume execution.
                0xEE => {
                    if (self.sp == 0) return error.StackUnderflow;
                    self.sp -= 1;
                    self.pc = self.stack[self.sp];
                },
                else => {},
            },

            // 1nnn - JP addr: unconditional jump to address nnn.
            0x1 => self.pc = @intCast(nnn),

            // 2nnn - CALL addr: push current pc onto stack, jump to nnn.
            0x2 => {
                if (self.sp >= 16) return error.StackOverflow;
                self.stack[self.sp] = self.pc;
                self.sp += 1;
                self.pc = @intCast(nnn);
            },

            // 3Xnn - SE Vx, byte: skip next instruction if Vx == nn.
            0x3 => if (self.v_regs[x] == nn) {
                self.pc += 2;
            },

            // 4Xnn - SNE Vx, byte: skip next instruction if Vx != nn.
            0x4 => if (self.v_regs[x] != nn) {
                self.pc += 2;
            },

            // 5XY0 - SE Vx, Vy: skip next instruction if Vx == Vy.
            0x5 => if (self.v_regs[x] == self.v_regs[y]) {
                self.pc += 2;
            },

            // 9XY0 - SNE Vx, Vy: skip next instruction if Vx != Vy.
            0x9 => if (self.v_regs[x] != self.v_regs[y]) {
                self.pc += 2;
            },

            // 6Xnn - LD Vx, byte: set Vx = nn.
            0x6 => self.v_regs[x] = nn,

            // 7Xnn - ADD Vx, byte: set Vx = Vx + nn, no carry flag.
            0x7 => self.v_regs[x] +%= nn,

            // Annn - LD I, addr: set index register I = nnn.
            0xA => self.i_reg = @intCast(nnn),

            // Bnnn - JP V0, addr: jump to address nnn + V0.
            0xB => self.pc = (@as(u16, nnn) +% self.v_regs[0]) & 0x0FFF,

            // DXYn - DRW Vx, Vy, n: draw N-byte sprite at (Vx, Vy); VF = collision.
            0xD => {
                const x_pos = self.v_regs[x] & @as(u8, DIS_W - 1);
                const y_pos = self.v_regs[y] & @as(u8, DIS_H - 1);
                var collision = false;

                for (0..n) |row| {
                    const sprite_byte = self.memory[self.i_reg + @as(u16, @intCast(row))];
                    for (0..8) |b| {
                        if (sprite_byte & (@as(u8, 0x80) >> @intCast(b)) != 0) {
                            const screen_x = x_pos + b;
                            const screen_y = y_pos + row;
                            if (screen_x < DIS_W and screen_y < DIS_H) {
                                const index = screen_x + (screen_y * DIS_W);
                                if (self.display[index]) collision = true;
                                self.display[index] ^= true;
                            }
                        }
                    }
                }
                self.v_regs[0xF] = if (collision) 1 else 0;
            },

            // 8XYn - arithmetic and bitwise ops on Vx and Vy; dispatch on n.
            0x8 => switch (n) {
                // 8XY0 - LD Vx, Vy: set Vx = Vy.
                0x0 => self.v_regs[x] = self.v_regs[y],
                // 8XY1 - OR Vx, Vy: set Vx = Vx | Vy.
                0x1 => self.v_regs[x] |= self.v_regs[y],
                // 8XY2 - AND Vx, Vy: set Vx = Vx & Vy.
                0x2 => self.v_regs[x] &= self.v_regs[y],
                // 8XY3 - XOR Vx, Vy: set Vx = Vx ^ Vy.
                0x3 => self.v_regs[x] ^= self.v_regs[y],
                // 8XY4 - ADD Vx, Vy: set Vx = Vx + Vy, VF = carry.
                0x4 => {
                    const val = @addWithOverflow(self.v_regs[x], self.v_regs[y]);
                    self.v_regs[x] = val[0];
                    self.v_regs[0xF] = @intFromBool(val[1] != 0);
                },
                // 8XY5 - SUB Vx, Vy: set Vx = Vx - Vy, VF = NOT borrow.
                0x5 => {
                    const val = @subWithOverflow(self.v_regs[x], self.v_regs[y]);
                    self.v_regs[x] = val[0];
                    self.v_regs[0xF] = if (val[1] != 0) 0 else 1;
                },
                // 8XY6 - SHR Vx: set Vx >>= 1, VF = shifted-out bit.
                0x6 => {
                    const shifted_out_bit = self.v_regs[x] & 0x1;
                    self.v_regs[x] >>= 1;
                    self.v_regs[0xF] = shifted_out_bit;
                },
                // 8XY7 - SUBN Vx, Vy: set Vx = Vy - Vx, VF = NOT borrow.
                0x7 => {
                    const val = @subWithOverflow(self.v_regs[y], self.v_regs[x]);
                    self.v_regs[x] = val[0];
                    self.v_regs[0xF] = if (val[1] != 0) 0 else 1;
                },
                // 8XYE - SHL Vx: set Vx <<= 1, VF = shifted-out bit.
                0xE => {
                    const shifted_out_bit = (self.v_regs[x] & 0x80) >> 7;
                    self.v_regs[x] <<= 1;
                    self.v_regs[0xF] = shifted_out_bit;
                },
                else => {},
            },

            // CXnn - RND Vx, byte: set Vx = random byte & nn.
            0xC => self.v_regs[x] = prng.random().int(u8) & nn,

            // EX9E and EXA1 skip based on key state in Vx; dispatch on nn.
            0xE => switch (nn) {
                // EX9E - SKP Vx: skip next instruction if key Vx is pressed.
                0x9E => {
                    const key = self.v_regs[x];
                    if (key < 16 and self.keypad[key]) self.pc += 2;
                },
                // EXA1 - SKNP Vx: skip next instruction if key Vx is not pressed.
                0xA1 => {
                    const key = self.v_regs[x];
                    if (key < 16 and !self.keypad[key]) self.pc += 2;
                },
                else => {},
            },

            // FXnn - timer, memory, I/O, and misc ops; dispatch on nn.
            0xF => switch (nn) {
                // FX07 - LD Vx, DT: set Vx = delay timer.
                0x07 => self.v_regs[x] = self.delay_timer,
                // FX15 - LD DT, Vx: set delay timer = Vx.
                0x15 => self.delay_timer = self.v_regs[x],
                // FX18 - LD ST, Vx: set sound timer = Vx.
                0x18 => self.sound_timer = self.v_regs[x],
                // FX1E - ADD I, Vx: set I = I + Vx.
                0x1E => self.i_reg +%= @intCast(self.v_regs[x]),
                // FX29 - LD F, Vx: set I = address of font sprite for digit Vx & 0xF.
                0x29 => self.i_reg = @intCast((self.v_regs[x] & 0xF) * 0x5),
                // FX55 - LD [I], Vx: store V0..Vx into memory starting at I.
                0x55 => {
                    for (0..x + 1) |i| self.memory[self.i_reg + i] = self.v_regs[i];
                },
                // FX65 - LD Vx, [I]: read V0..Vx from memory starting at I.
                0x65 => {
                    for (0..x + 1) |i| self.v_regs[i] = self.memory[self.i_reg + i];
                },
                // FX33 - LD B, Vx: store BCD digits of Vx at I, I+1, I+2 via double-dabble.
                0x33 => {
                    var val = self.v_regs[x];
                    var hundreds: u8 = 0;
                    var tens: u8 = 0;
                    var ones: u8 = 0;

                    for (0..8) |_| {
                        if (hundreds >= 5) hundreds += 3;
                        if (tens >= 5) tens += 3;
                        if (ones >= 5) ones += 3;

                        const bit = (val & 0x80) >> 7;
                        val <<= 1;

                        ones = (ones << 1) | bit;
                        tens = (tens << 1) | (ones >> 4);
                        hundreds = (hundreds << 1) | (tens >> 4);

                        ones &= 0x0F;
                        tens &= 0x0F;
                        hundreds &= 0x0F;
                    }

                    self.memory[self.i_reg] = hundreds;
                    self.memory[self.i_reg + 1] = tens;
                    self.memory[self.i_reg + 2] = ones;
                },
                // FX0A - LD Vx, K: halt execution until a key is pressed; store key in Vx.
                0x0A => {
                    self.waiting_for_key = true;
                    self.waiting_reg = @intCast(x);
                },
                else => {},
            },
            else => return error.InvalidOpcode,
        }
    }
};
