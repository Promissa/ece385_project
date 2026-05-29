# Lab 9 Progress Report

Date: 2026-05-06

## Current Working VGA Test

The pure Lab 9 VGA software test is separated from the USB keyboard migration work. It builds `lab9_vga_demo.elf` and uses only the Lab 9 text-mode VGA software:

- `software/text_mode/lab9_vga_demo.c`
- `software/text_mode/text_mode_vga_color.c`
- `software/text_mode/palette_test.c`

To build and run the pure VGA test in the Nios II command shell:

```bash
cd /cygdrive/e/root/2026/385/lab9_zzy/ece385_lab9_1_provided/software/text_mode
make TEST_MODE=lab9 clean_all
make TEST_MODE=lab9
nios2-download -g lab9_vga_demo.elf
nios2-terminal
```

Expected terminal message:

```text
Running Lab 9 Week 2 teacher VGA demo...
```

Expected VGA behavior:

- `paletteTest()` runs first.
- Then `textVGAColorScreenSaver()` runs.
- This test does not use USB keyboard code.
- This test should not build or download `keyboard_test.elf`.

## Compile Report and SDC Notes

Two Lab 9 project copies were compared after full Quartus compilation:

- Week1 recovered project: `E:\root\2026\385\lab9_zzy\ece385_lab9_1\ece385_lab9_1_provided`
- Week2 working project: `E:\root\2026\385\lab9_zzy\ece385_lab9_1_provided`

Both projects compiled successfully and generated `.sof` files, but their timing reports are very different.

| Project | Compile status | Logic elements | Registers | Pins | Memory bits | PLLs | Main `Clk` timing |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Week1 recovered | Successful, May 6 21:12:37 2026 | 38,547 / 114,480, 34% | 20,696 | 105 / 529, 20% | 11,392 | 1 / 4 | Failed |
| Week2 working | Successful, May 6 20:15:51 2026 | 4,041 / 114,480, 4% | 1,889 | 135 / 529, 26% | 76,928 | 1 / 4 | Passed |

Timing Analyzer summary:

| Project | Slow 1200 mV 85 C setup slack | TNS | Reported `Clk` Fmax | Interpretation |
| --- | ---: | ---: | ---: | --- |
| Week1 recovered | -8.572 ns | -99.785 ns | 35.0 MHz | Not timing clean at 50 MHz |
| Week2 working | +1.705 ns | 0 ns | 54.66 MHz | Main 50 MHz domain meets timing |

The Week1 timing failure is meaningful: its worst paths go from the VGA text interface local/register storage toward VGA color output pins, matching the earlier bug pattern where the scanout path was too large and not implemented as a clean memory pipeline. The Week2 design moved the text buffer into true dual-port `altsyncram`, which reduced logic usage and allowed the main 50 MHz domain to meet timing.

However, the SDC is not fully correct in either project. Both `lab9.sdc` files still contain a stale generated-clock constraint:

```tcl
create_generated_clock -name {lab9_qsystem|altpll_0|sd1|pll|clk[0]} ...
```

The current Platform Designer hierarchy is `lab9_soc`, not `lab9_qsystem`, so Quartus reports that this generated clock filter cannot be matched. Quartus also warns that the VGA controller's fabric-divided `clkdiv` was detected as a clock but has no associated clock assignment, and that the SDRAM PLL generated clock is missing. Quartus also recommends clock uncertainty constraints.

This means the compile report is not useless, but it is not a complete timing signoff:

- Resource usage, pin usage, memory usage, PLL count, and whether a `.sof` was generated are still valid.
- The `CLOCK_50` main clock is constrained with `create_clock -period 20.000`, so the main `Clk` setup/hold report is meaningful.
- Week2's positive `Clk` slack is a real improvement over Week1 and supports hardware testing.
- Generated-clock timing for the SDRAM PLL and VGA `clkdiv` is incomplete, so those parts of STA should not be treated as final signoff.

Recommended SDC cleanup before final submission:

1. Replace the stale `lab9_qsystem|altpll_0` generated-clock path with the current `lab9_soc` PLL hierarchy, or use Quartus-derived PLL constraints such as `derive_pll_clocks` if accepted by the lab toolflow.
2. Add `derive_clock_uncertainty`.
3. Prefer changing VGA scanout from `always_ff @(posedge clkdiv)` to a clock-enable style under `CLOCK_50`, or generate a real 25 MHz pixel clock with a PLL and constrain it. If `clkdiv` remains a fabric clock, add an explicit generated-clock constraint for it.
4. In the final report, state that Week2 passed full compile and met the constrained 50 MHz main clock, while generated-clock constraints still produced warnings and therefore hardware testing was used for functional confirmation.

## Hardware Changes Made

The Lab 9 Qsys/Quartus project was extended with Lab 8 USB keyboard hardware support while keeping the existing VGA text-mode controller.

Main hardware files affected:

- `lab9.sv`
- `hpi_io_intf.sv`
- `Lab9.qsf`
- `lab9_soc.qsys`

Summary of hardware changes:

- Added CY7C67200 USB-OTG/HPI top-level ports to `lab9.sv`.
- Instantiated the Lab 8 `hpi_io_intf` module in `lab9.sv`.
- Connected the HPI interface to Qsys PIO exports:
  - `otg_hpi_address`
  - `otg_hpi_data_in`
  - `otg_hpi_data_out`
  - `otg_hpi_r`
  - `otg_hpi_w`
  - `otg_hpi_cs`
  - `otg_hpi_reset`
- Kept `keycode` as an 8-bit PIO output to drive `HEX0/HEX1`.
- Added OTG pin assignments and I/O standards to `Lab9.qsf`.
- Assigned the HPI PIO base addresses in Qsys and regenerated HDL.

Known hardware warning status:

- VGA low nibble pins stuck at GND are expected because Lab 9 drives only `VGA_R/G/B[7:4]`.
- `OTG_DACK_N[1:0]` stuck at VCC is expected because they are tied high.
- Unused OTG interrupt/status inputs are expected for the current polling-based Lab 8 software.
- SDRAM/PLL/SDC warnings are inherited from the generated platform and are not currently blocking.

## Software Structure Changes

The original single software project was split into explicit build modes in `software/text_mode/Makefile`:

```bash
make TEST_MODE=keyboard
make TEST_MODE=lab9
make TEST_MODE=mixed
```

Build outputs:

- `keyboard_test.elf`: USB keyboard-only migration test.
- `lab9_vga_demo.elf`: pure Lab 9 teacher VGA demo.
- `mixed_keyboard_vga_test.elf`: combined VGA + keyboard test.

This avoids confusing `text_mode.elf` with different test purposes.

## VGA Bugs and Fix Process

This is the main Lab 9 debugging record. The goal was to make the text-mode VGA controller work with the teacher-provided C tests and show readable 80x30 character text on the monitor.

### 1. Avalon-MM base address assignment failed

Symptom:

- Platform Designer / Qsys reported that `VGA_text_mode_controller_0.avl_mm_slave` could not be placed at the originally assigned address.
- The error message said the VGA slave could not be at `0x1000`; acceptable aligned positions were `0x0` or `0x4000`.

Cause:

- The VGA text-mode controller exposes a 16 KB Avalon-MM address span.
- The address must be aligned to the component span. Placing it at `0x1000` overlaps the required alignment boundary.

Fix:

- Reassigned the VGA text-mode controller to a 16 KB-aligned range.
- The generated BSP now shows:

```c
#define VGA_TEXT_MODE_CONTROLLER_0_BASE 0x10000000
#define VGA_TEXT_MODE_CONTROLLER_0_SPAN 16384
```

Result:

- Qsys HDL generation succeeded after assigning the base address and regenerating HDL.

### 2. `altsyncram` VRAM could not elaborate

Symptom:

- Quartus Analysis & Synthesis failed with errors around the VGA text-mode controller VRAM:

```text
Must connect clock1 port of altsyncram megafunction when using current set of parameters
Cannot use different clock ports for address_b port and data_b|wren_b|byteena_b port
Can't elaborate user hierarchy ... altsyncram:vram_mem
```

Cause:

- The VGA VRAM needs two access paths:
  - CPU/Avalon side writes and reads character/color words.
  - VGA scanout side continuously reads the word for the current screen position.
- The first implementation of the `altsyncram` instance did not fully match Quartus's required dual-port clock/control parameters.

Fix:

- Reworked `vga_text_avl_interface.sv` so VRAM is an explicit dual-port `altsyncram`.
- Connected both `clock0` and `clock1` to the system clock.
- Put CPU access on port A and VGA scanout on port B.
- Disabled port B writes with `wren_b = 1'b0`.
- Set the important parameters explicitly:
  - `operation_mode = "BIDIR_DUAL_PORT"`
  - `numwords_a/b = 2048`
  - `width_a/b = 32`
  - `widthad_a/b = 11`
  - `width_byteena_a = 4`
  - `ram_block_type = "M9K"`

Result:

- Quartus full compilation passed after the VRAM clock/port configuration was fixed.

### 3. VRAM and palette memory map had to match the C driver

Symptom:

- The C tests write through `text_mode_vga_color.c`, so hardware and software must agree on the exact word layout.
- If the address split or byte packing is wrong, text becomes unreadable, colors appear wrong, or palette writes affect character memory.

Required memory map:

```text
0x000-0x4AF : VRAM, 80x30 characters, 2 characters per 32-bit word
0x800-0x807 : 16-color palette, 2 colors per 32-bit word
```

Required VRAM word format:

```text
[31]    [30:24] [23:20] [19:16] [15]    [14:8] [7:4] [3:0]
invert1 code1   fg1     bg1     invert0 code0  fg0   bg0
```

Fix:

- In `vga_text_avl_interface.sv`, `AVL_ADDR[11]` selects between VRAM and palette space.
- VRAM writes are allowed only when `AVL_ADDR < 1200`.
- Palette writes are allowed only for the eight palette words.
- Added byte-enable merging for palette writes so software byte writes do not destroy the other color stored in the same 32-bit palette word.

Result:

- The teacher C functions can clear VRAM, draw text, and update palette entries correctly.

### 4. Screen coordinate to VRAM index conversion

Symptom:

- The text-mode display must convert 640x480 pixels into 80x30 text cells.
- A wrong row/column calculation causes repeated letters, shifted rows, or broken line wrapping.

Fix:

- Used 8x16 character cells:

```text
char_col = draw_x[9:3]
char_row = draw_y[8:4]
```

- Converted text cell position to word address using:

```text
word_index = row * 40 + col / 2
```

- Implemented the multiplication as shifts and adds:

```systemverilog
draw_word_index = row * 32 + row * 8 + col[6:1]
```

Result:

- Characters are read from the expected VRAM word and half-word.
- Text appears in row/column order instead of scrambled positions.

### 5. One-cycle VGA pipeline alignment

Symptom:

- Font ROM and VRAM reads are not purely instantaneous in the practical display pipeline.
- If the current pixel coordinate is mixed with the previous cycle's character data, glyph pixels and colors can be shifted or visually noisy.

Fix:

- Registered the scanout metadata in `vga_text_avl_interface.sv`:
  - `draw_half_select_d`
  - `draw_x_bit_d`
  - `draw_y_row_d`
  - `blank_d`
  - `visible_d`
- Used the delayed signals when selecting the character half-word, font bit, and output color.

Result:

- The font bitmap and selected foreground/background color line up with the intended pixel.

### 6. VGA output width warning was expected

Symptom:

- Quartus reported VGA output pins stuck at GND for `VGA_R/G/B[3:0]`.

Cause:

- The Lab 9 VGA text-mode controller outputs 4 bits per color channel.
- The DE2-115 VGA port exposes 8 bits per channel.

Fix:

- Connected controller outputs to the upper nibbles:

```systemverilog
.vga_port_red   (VGA_R[7:4])
.vga_port_green (VGA_G[7:4])
.vga_port_blue  (VGA_B[7:4])
```

- Tied the lower nibbles to zero:

```systemverilog
assign VGA_R[3:0] = 4'h0;
assign VGA_G[3:0] = 4'h0;
assign VGA_B[3:0] = 4'h0;
```

Result:

- The stuck-at-GND warning for the lower VGA bits is expected and not a functional error.

### 7. Test selection confusion: `palette_test` vs. the full VGA demo

Symptom:

- Running the palette-only test made the screen look different from classmates' demos.
- It could show only a small amount of intentional text and color cycling behavior, which was easy to misinterpret as a display bug.

Cause:

- `paletteTest()` is only a palette stress test.
- The full teacher Week 2 demo uses both `paletteTest()` and `textVGAColorScreenSaver()`.

Fix:

- Added `lab9_vga_demo.c` as a clean entry point:

```c
int main(void)
{
    printf("Running Lab 9 Week 2 teacher VGA demo...\n");
    paletteTest();
    textVGAColorScreenSaver();
    while (1) {
    }
}
```

- Updated the Makefile so the pure VGA demo builds as its own ELF:

```bash
make TEST_MODE=lab9
```

Result:

- The VGA demo is now separated from keyboard work and can be tested independently with `lab9_vga_demo.elf`.

## USB Keyboard Migration Work

Lab 8 USB files were copied into the Lab 9 software project:

- `cy7c67200.h`
- `io_handler.c`
- `io_handler.h`
- `lcp_cmd.h`
- `lcp_data.h`
- `usb.c`
- `usb.h`
- `usb_keyboard.c`
- `usb_keyboard.h`

The original Lab 8 `main.c` logic was converted into:

```c
int usb_keyboard_run(void)
```

This allows keyboard code to be called from either a keyboard-only test or a mixed VGA/keyboard test.

## USB Debug Fixes Made

A keyboard-only test was added:

- `software/text_mode/keyboard_test.c`

It performs:

- A `keycode` PIO self-test on `HEX0/HEX1`.
- HPI probe prints.
- Lab 8 USB initialization and keyboard enumeration.
- HID keycode callback prints when the polling loop is reached.

Fixes made during debugging:

- Added missing `usb.h` include in `keyboard_test.c` so `HPI_MAILBOX` and `HPI_STATUS` are defined.
- Restored `io_handler.h` pointer types to match Lab 8 style:
  - 16-bit/2-bit PIOs use `volatile int*`.
  - 1-bit control PIOs use `volatile char*`.
  - `keycode_base` uses `volatile char*`.
- Added timeout diagnostics to `UsbWaitTDListDone()` in `usb.c`.
- Fixed `UsbWaitTDListDone()` to test the `HUSB_TDListDone` bit instead of requiring equality with `0x1000`.
  - This fixed the observed case where `SIE1 msg = 0xffff` actually contained the done bit.
- Updated `UsbGetRetryCnt()` to use the same bit-based done check.
- Added Step 7/8/9 timeout and progress messages in `usb_keyboard.c`.
- Added a clear message when the program enters the key polling loop.
- Improved keycode extraction by checking the low byte first and then the high byte if the low byte is zero.

Current USB status:

- USB enumeration now reaches:
  - Set address.
  - Device descriptor 1.
  - Device descriptor 2.
  - Configuration descriptor 1.
  - Configuration descriptor 2.
  - Keyboard detected.
  - Data packet size 8.
- Remaining issue: the keyboard test still needs confirmation that it reaches the final key polling loop and updates HEX on key press.

## Recommended Next Steps

1. For grading/demo safety, use `TEST_MODE=lab9` and verify the VGA text-mode demo first.
2. Continue keyboard integration only after the VGA demo is stable.
3. For keyboard debugging, rebuild `keyboard_test.elf` and check whether this line appears:

```text
[KEYBOARD]: entering key polling loop; press A/B/arrows and watch HEX0/HEX1
```

4. After keyboard-only works, test `mixed_keyboard_vga_test.elf`.
