	lab9_soc u0 (
		.clk_clk            (<connected-to-clk_clk>),            //        clk.clk
		.keycode_export     (<connected-to-keycode_export>),     //    keycode.export
		.reset_reset_n      (<connected-to-reset_reset_n>),      //      reset.reset_n
		.sdram_clk_clk      (<connected-to-sdram_clk_clk>),      //  sdram_clk.clk
		.sdram_wire_addr    (<connected-to-sdram_wire_addr>),    // sdram_wire.addr
		.sdram_wire_ba      (<connected-to-sdram_wire_ba>),      //           .ba
		.sdram_wire_cas_n   (<connected-to-sdram_wire_cas_n>),   //           .cas_n
		.sdram_wire_cke     (<connected-to-sdram_wire_cke>),     //           .cke
		.sdram_wire_cs_n    (<connected-to-sdram_wire_cs_n>),    //           .cs_n
		.sdram_wire_dq      (<connected-to-sdram_wire_dq>),      //           .dq
		.sdram_wire_dqm     (<connected-to-sdram_wire_dqm>),     //           .dqm
		.sdram_wire_ras_n   (<connected-to-sdram_wire_ras_n>),   //           .ras_n
		.sdram_wire_we_n    (<connected-to-sdram_wire_we_n>),    //           .we_n
		.vga_port_blue      (<connected-to-vga_port_blue>),      //   vga_port.blue
		.vga_port_green     (<connected-to-vga_port_green>),     //           .green
		.vga_port_hs        (<connected-to-vga_port_hs>),        //           .hs
		.vga_port_red       (<connected-to-vga_port_red>),       //           .red
		.vga_port_vs        (<connected-to-vga_port_vs>),        //           .vs
		.vga_port_blank     (<connected-to-vga_port_blank>),     //           .blank
		.vga_port_pixel_clk (<connected-to-vga_port_pixel_clk>), //           .pixel_clk
		.vga_port_sync      (<connected-to-vga_port_sync>)       //           .sync
	);

