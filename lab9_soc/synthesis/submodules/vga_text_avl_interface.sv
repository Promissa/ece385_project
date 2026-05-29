/************************************************************************
Avalon-MM Interface VGA Text mode display

Lab 9 Week 2 color text mode.

Memory map, word addresses:
0x000-0x4AF : VRAM, 80x30 characters, 2 characters per word
0x4B0-0x7FF : reserved
0x800-0x807 : 16-color palette, 2 colors per word
0x808-0xFFF : reserved

VRAM Format:
[31][30:24][23:20][19:16][15][14:8][7:4][3:0]
 IV1 CODE1  FGD1   BKG1   IV0 CODE0 FGD0 BKG0

Palette Format:
[24:21][20:17][16:13] = odd color RGB
[12:9 ][8:5  ][4:1  ] = even color RGB
************************************************************************/

module vga_text_avl_interface (
    input  logic        CLK,
    input  logic        RESET,

    input  logic        AVL_READ,
    input  logic        AVL_WRITE,
    input  logic        AVL_CS,
    input  logic [3:0]  AVL_BYTE_EN,
    input  logic [11:0] AVL_ADDR,
    input  logic [31:0] AVL_WRITEDATA,
    output logic [31:0] AVL_READDATA,

    output logic [3:0]  red,
    output logic [3:0]  green,
    output logic [3:0]  blue,
    output logic        hs,
    output logic        vs,
    output logic        sync,
    output logic        blank,
    output logic        pixel_clk
);

    localparam int VRAM_WORDS    = 1200;
    localparam int PALETTE_WORDS = 8;

    logic [31:0] palette [0:PALETTE_WORDS-1];
    logic [31:0] vram_cpu_readdata;
    logic [31:0] vram_draw_word;
    logic [10:0] vram_cpu_addr;
    logic [10:0] vram_draw_addr;
    logic        vram_write_en;

    logic [9:0]  draw_x, draw_y;
    logic [10:0] font_addr;
    logic [7:0]  font_data;

    logic [4:0]  char_row;
    logic [6:0]  char_col;
    logic [10:0] draw_word_index;
    logic        draw_half_select;

    logic [31:0] draw_word;
    logic        draw_half_select_d;
    logic [2:0]  draw_x_bit_d;
    logic [3:0]  draw_y_row_d;
    logic        blank_d;
    logic        visible_d;

    logic [15:0] char_cell;
    logic [6:0]  glyph_code;
    logic        invert_pixel;
    logic [3:0]  foreground_idx;
    logic [3:0]  background_idx;
    logic [3:0]  selected_idx;
    logic [11:0] selected_rgb;
    logic        glyph_pixel;

    assign vram_cpu_addr  = AVL_ADDR[10:0];
    assign vram_draw_addr = draw_word_index;
    assign vram_write_en  = AVL_CS && AVL_WRITE && !AVL_ADDR[11] && (AVL_ADDR < VRAM_WORDS);
    assign draw_word      = vram_draw_word;

    altsyncram vram_mem (
        .address_a (vram_cpu_addr),
        .address_b (vram_draw_addr),
        .byteena_a (AVL_BYTE_EN),
        .clock0    (CLK),
        .clock1    (CLK),
        .data_a    (AVL_WRITEDATA),
        .data_b    (32'h0000_0000),
        .q_a       (vram_cpu_readdata),
        .q_b       (vram_draw_word),
        .wren_a    (vram_write_en),
        .wren_b    (1'b0)
    );

    defparam vram_mem.address_reg_b = "CLOCK1",
             vram_mem.byte_size = 8,
             vram_mem.lpm_type = "altsyncram",
             vram_mem.maximum_depth = 2048,
             vram_mem.numwords_a = 2048,
             vram_mem.numwords_b = 2048,
             vram_mem.operation_mode = "BIDIR_DUAL_PORT",
             vram_mem.outdata_reg_a = "UNREGISTERED",
             vram_mem.outdata_reg_b = "UNREGISTERED",
             vram_mem.rdcontrol_reg_b = "CLOCK1",
             vram_mem.ram_block_type = "M9K",
             vram_mem.read_during_write_mode_mixed_ports = "DONT_CARE",
             vram_mem.read_during_write_mode_port_a = "DONT_CARE",
             vram_mem.read_during_write_mode_port_b = "DONT_CARE",
             vram_mem.wrcontrol_wraddress_reg_b = "CLOCK1",
             vram_mem.width_a = 32,
             vram_mem.width_b = 32,
             vram_mem.width_byteena_a = 4,
             vram_mem.widthad_a = 11,
             vram_mem.widthad_b = 11;

    vga_controller vga_ctrl (
        .Clk       (CLK),
        .Reset     (RESET),
        .hs        (hs),
        .vs        (vs),
        .pixel_clk (pixel_clk),
        .blank     (blank),
        .sync      (sync),
        .DrawX     (draw_x),
        .DrawY     (draw_y)
    );

    font_rom font0 (
        .addr (font_addr),
        .data (font_data)
    );

    function automatic logic [11:0] palette_rgb(input logic [3:0] idx);
        logic [31:0] palette_word;
        begin
            palette_word = palette[idx[3:1]];
            if (idx[0])
                palette_rgb = {palette_word[24:21], palette_word[20:17], palette_word[16:13]};
            else
                palette_rgb = {palette_word[12:9], palette_word[8:5], palette_word[4:1]};
        end
    endfunction

    function automatic logic [31:0] byte_merge(
        input logic [31:0] old_word,
        input logic [31:0] new_word,
        input logic [3:0]  byte_en
    );
        begin
            byte_merge = old_word;
            if (byte_en[0]) byte_merge[7:0]   = new_word[7:0];
            if (byte_en[1]) byte_merge[15:8]  = new_word[15:8];
            if (byte_en[2]) byte_merge[23:16] = new_word[23:16];
            if (byte_en[3]) byte_merge[31:24] = new_word[31:24];
        end
    endfunction

    always_comb begin
        char_row        = draw_y[8:4];
        char_col        = draw_x[9:3];
        draw_half_select = char_col[0];

        // word_index = row * 40 + col / 2 = row * 32 + row * 8 + col[6:1]
        draw_word_index = {1'b0, char_row, 5'b00000}
                        + {3'b000, char_row, 3'b000}
                        + {5'b00000, char_col[6:1]};

        char_cell = draw_half_select_d ? draw_word[31:16] : draw_word[15:0];

        invert_pixel   = char_cell[15];
        glyph_code     = char_cell[14:8];
        foreground_idx = char_cell[7:4];
        background_idx = char_cell[3:0];

        font_addr    = {glyph_code, draw_y_row_d};
        glyph_pixel  = font_data[3'd7 - draw_x_bit_d];
        selected_idx = (glyph_pixel ^ invert_pixel) ? foreground_idx : background_idx;
        selected_rgb = palette_rgb(selected_idx);
    end

    always_ff @(posedge CLK) begin
        if (RESET) begin
            palette[0] <= 32'h0001_C000; // 0 black, 1 blue
            palette[1] <= 32'h001D_C1C0; // 2 green, 3 cyan
            palette[2] <= 32'h01C1_DC00; // 4 red, 5 magenta
            palette[3] <= 32'h01DD_DDC0; // 6 yellow, 7 white
            palette[4] <= 32'h0001_EEEE; // 8 gray, 9 bright blue
            palette[5] <= 32'h001F_E1E0; // 10 bright green, 11 bright cyan
            palette[6] <= 32'h01E1_FE00; // 12 bright red, 13 bright magenta
            palette[7] <= 32'h01FF_FFE0; // 14 bright yellow, 15 bright white
            AVL_READDATA <= 32'h0000_0000;

            draw_half_select_d <= 1'b0;
            draw_x_bit_d      <= 3'b000;
            draw_y_row_d      <= 4'b0000;
            blank_d           <= 1'b0;
            visible_d         <= 1'b0;
        end
        else begin
            if (AVL_CS && AVL_WRITE) begin
                if (AVL_ADDR[11] && (AVL_ADDR[10:0] < PALETTE_WORDS)) begin
                    palette[AVL_ADDR[2:0]] <= byte_merge(palette[AVL_ADDR[2:0]], AVL_WRITEDATA, AVL_BYTE_EN);
                end
            end

            if (AVL_CS && AVL_READ) begin
                if (!AVL_ADDR[11] && (AVL_ADDR < VRAM_WORDS))
                    AVL_READDATA <= vram_cpu_readdata;
                else if (AVL_ADDR[11] && (AVL_ADDR[10:0] < PALETTE_WORDS))
                    AVL_READDATA <= palette[AVL_ADDR[2:0]];
                else
                    AVL_READDATA <= 32'h0000_0000;
            end

            draw_half_select_d <= draw_half_select;
            draw_x_bit_d       <= draw_x[2:0];
            draw_y_row_d       <= draw_y[3:0];
            blank_d            <= blank;
            visible_d          <= (draw_x < 10'd640) && (draw_y < 10'd480);
        end
    end

    always_ff @(posedge CLK or posedge RESET) begin
        if (RESET) begin
            red   <= 4'h0;
            green <= 4'h0;
            blue  <= 4'h0;
        end
        else if (!blank_d || !visible_d) begin
            red   <= 4'h0;
            green <= 4'h0;
            blue  <= 4'h0;
        end
        else begin
            red   <= selected_rgb[11:8];
            green <= selected_rgb[7:4];
            blue  <= selected_rgb[3:0];
        end
    end

endmodule
