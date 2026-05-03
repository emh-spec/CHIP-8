# CHIP-8 Emulator

A CHIP-8 emulator written in Zig.

## Features

- All 35 CHIP-8 opcodes
- 64x32 display scaled to 640x320
- 16-key hex keypad input
- Sound timer with square wave beep
- 700Hz CPU clock, 60Hz frame rate

## Requirements

- Zig `0.16.0`
- SDL2 (`libsdl2-dev` on Debian/Ubuntu)

## Installation

Download the `zig` binary from the download [page](https://ziglang.org/download/#release-0.16.0).

```bash
sudo apt install libsdl2-dev
```

## Building

Optimization is based on how you want to build. (`Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall`). 

```bash
zig build -Doptimize=ReleaseSafe
```

Binary will be at `zig-out/bin/chip8`.

## Usage

```bash
./zig-out/bin/chip8 <path_to_rom>
```
There are some ROM given in the [roms](roms/) dir. Use them or use your own. 

Press `Escape` or close the window to quit.

## Keymap

```
CHIP-8    Keyboard
──────    ────────
1 2 3 4   1 2 3 4
5 6 7 8   Q W E R
9 A B C   A S D F
D E F 0   Z X C V
```
