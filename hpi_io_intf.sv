module hpi_io_intf( input               Clk, Reset,
                    input  logic [1:0]  from_sw_address,
                    output logic [15:0] from_sw_data_in,
                    input  logic [15:0] from_sw_data_out,
                    input  logic        from_sw_r, from_sw_w, from_sw_cs, from_sw_reset,
                    inout  wire  [15:0] OTG_DATA,
                    output logic [1:0]  OTG_ADDR,
                    output logic        OTG_RD_N, OTG_WR_N, OTG_CS_N, OTG_RST_N
                   );

logic [15:0] from_sw_data_out_buffer;

always_ff @ (posedge Clk)
begin
    if(Reset)
    begin
        from_sw_data_out_buffer <= 16'h0000;
        OTG_ADDR                <= 2'b00;
        OTG_RD_N                <= 1'b1;
        OTG_WR_N                <= 1'b1;
        OTG_CS_N                <= 1'b1;
        OTG_RST_N               <= 1'b0;
        from_sw_data_in         <= 16'h0000;
    end
    else 
    begin
        from_sw_data_out_buffer <= from_sw_data_out;
        OTG_ADDR                <= from_sw_address;
        OTG_RD_N                <= from_sw_r;
        OTG_WR_N                <= from_sw_w;
        OTG_CS_N                <= from_sw_cs;
        OTG_RST_N               <= from_sw_reset;
        from_sw_data_in         <= OTG_DATA;
    end
end

// Only drive OTG_DATA when writing (from_sw_w active low = 0)
assign OTG_DATA = (from_sw_w == 1'b0) ? from_sw_data_out_buffer : 16'hZZZZ;

endmodule
