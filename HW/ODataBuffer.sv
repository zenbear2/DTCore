module ODB #(
    parameter DWIDTH = 128
)(
    input                     clk,
    input                     rst_n,
    input  wire               wr_en,
    input  wire               rd_en,
    input  wire[DWIDTH-1:0]   din,
    output wire[DWIDTH-1:0]   dout,
    output wire               empty,
    output wire               full,
    output wire               data_valid
);


fifo_sync #(
    .ADDR_WIDTH(9),
    .DWIDTH(DWIDTH)
) sync_fifo_inst (
    .rst_n      (rst_n),
    .clk        (clk),
    .wr_en      (wr_en),
    .rd_en      (rd_en),
    .din        (din),
    .dout       (dout),
    .empty      (empty),
    .full       (full),
    .data_valid (data_valid)
);


endmodule