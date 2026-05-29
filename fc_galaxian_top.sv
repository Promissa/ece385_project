//-------------------------------------------------------------------------
// FC Galaxian-inspired final project top level for the DE2-115.
//
// This keeps the Lab 9 Nios/USB-HPI block for keyboard input and moves the
// playable game loop and VGA rendering into SystemVerilog hardware.
//-------------------------------------------------------------------------

module fc_galaxian_top(
    input               CLOCK_50,
    input        [3:0]  KEY,
    input        [17:0] SW,
    output logic [6:0]  HEX0, HEX1, HEX2, HEX3,
                        HEX4, HEX5, HEX6, HEX7,

    // CY7C67200 USB-OTG/HPI interface for keyboard support
    inout  wire  [15:0] OTG_DATA,
    output logic [1:0]  OTG_ADDR,
    output logic        OTG_CS_N,
                        OTG_OE_N,
                        OTG_WE_N,
                        OTG_RST_N,
    input        [1:0]  OTG_INT,
    input        [1:0]  OTG_DREQ,
    output logic [1:0]  OTG_DACK_N,
    input               OTG_FSPEED,
                        OTG_LSPEED,

    // SDRAM interface for the Nios II USB software
    output logic [12:0] DRAM_ADDR,
    inout  wire  [31:0] DRAM_DQ,
    output logic [1:0]  DRAM_BA,
    output logic [3:0]  DRAM_DQM,
    output logic        DRAM_RAS_N,
                        DRAM_CAS_N,
                        DRAM_CKE,
                        DRAM_WE_N,
                        DRAM_CS_N,
                        DRAM_CLK,

    // VGA output
    output logic [7:0]  VGA_R,
                        VGA_G,
                        VGA_B,
    output logic        VGA_CLK,
                        VGA_HS,
                        VGA_VS,
                        VGA_BLANK_N,
                        VGA_SYNC_N
);

    logic       clk;
    logic       reset_n;
    logic [7:0] keycode;
    logic [3:0] difficulty_level;

    logic [1:0]  hpi_addr;
    logic [15:0] hpi_data_in, hpi_data_out;
    logic        hpi_r, hpi_w, hpi_cs, hpi_reset;

    logic [3:0] game_red, game_green, game_blue;

    // The generated SoC still exposes its Lab 9 text-mode VGA conduit.
    // The final-project renderer drives the physical VGA pins instead.
    logic [3:0] vga_red_unused, vga_green_unused, vga_blue_unused;
    logic       vga_hs_unused, vga_vs_unused, vga_clk_unused;
    logic       vga_blank_unused, vga_sync_unused;

    assign clk        = CLOCK_50;
    assign reset_n    = KEY[0];
    assign OTG_DACK_N = 2'b11;

    assign VGA_R = {game_red, game_red};
    assign VGA_G = {game_green, game_green};
    assign VGA_B = {game_blue, game_blue};

    hpi_io_intf hpi_io_inst (
        .Clk              (clk),
        .Reset            (~reset_n),
        .from_sw_address  (hpi_addr),
        .from_sw_data_in  (hpi_data_in),
        .from_sw_data_out (hpi_data_out),
        .from_sw_r        (hpi_r),
        .from_sw_w        (hpi_w),
        .from_sw_cs       (hpi_cs),
        .from_sw_reset    (hpi_reset),
        .OTG_DATA         (OTG_DATA),
        .OTG_ADDR         (OTG_ADDR),
        .OTG_RD_N         (OTG_OE_N),
        .OTG_WR_N         (OTG_WE_N),
        .OTG_CS_N         (OTG_CS_N),
        .OTG_RST_N        (OTG_RST_N)
    );

    lab9_soc u0 (
        .clk_clk                 (clk),
        .keycode_export          (keycode),
        .otg_hpi_address_export  (hpi_addr),
        .otg_hpi_cs_export       (hpi_cs),
        .otg_hpi_data_in_export  (hpi_data_in),
        .otg_hpi_data_out_export (hpi_data_out),
        .otg_hpi_r_export        (hpi_r),
        .otg_hpi_reset_export    (hpi_reset),
        .otg_hpi_w_export        (hpi_w),
        .reset_reset_n           (reset_n),
        .sdram_clk_clk           (DRAM_CLK),
        .sdram_wire_addr         (DRAM_ADDR),
        .sdram_wire_ba           (DRAM_BA),
        .sdram_wire_cas_n        (DRAM_CAS_N),
        .sdram_wire_cke          (DRAM_CKE),
        .sdram_wire_cs_n         (DRAM_CS_N),
        .sdram_wire_dq           (DRAM_DQ),
        .sdram_wire_dqm          (DRAM_DQM),
        .sdram_wire_ras_n        (DRAM_RAS_N),
        .sdram_wire_we_n         (DRAM_WE_N),
        .vga_port_red            (vga_red_unused),
        .vga_port_green          (vga_green_unused),
        .vga_port_blue           (vga_blue_unused),
        .vga_port_hs             (vga_hs_unused),
        .vga_port_vs             (vga_vs_unused),
        .vga_port_pixel_clk      (vga_clk_unused),
        .vga_port_blank          (vga_blank_unused),
        .vga_port_sync           (vga_sync_unused)
    );

    fc_galaxian_game game (
        .clk              (clk),
        .reset_n          (reset_n),
        .keycode          (keycode),
        .switches         (SW),
        .difficulty_level (difficulty_level),
        .red              (game_red),
        .green            (game_green),
        .blue             (game_blue),
        .hs               (VGA_HS),
        .vs               (VGA_VS),
        .pixel_clk        (VGA_CLK),
        .blank            (VGA_BLANK_N),
        .sync             (VGA_SYNC_N)
    );

    HexDriver hex0 (.In0({2'b00, SW[9:8]} + 4'd1),  .Out0(HEX0)); // player bullet count preview
    HexDriver hex1 (.In0(4'hC),                     .Out0(HEX1)); // player config
    HexDriver hex2 (.In0({2'b00, SW[13:12]} + 4'd1), .Out0(HEX2)); // enemy bullet count preview
    HexDriver hex3 (.In0(4'hE),                     .Out0(HEX3)); // enemy config
    HexDriver hex4 (.In0({2'b00, SW[15:14]}),       .Out0(HEX4)); // formation mode preview
    HexDriver hex5 (.In0(4'hF),                     .Out0(HEX5)); // formation
    HexDriver hex6 (.In0(difficulty_level),         .Out0(HEX6)); // effective difficulty
    HexDriver hex7 (.In0(4'hD),                     .Out0(HEX7)); // difficulty

endmodule
