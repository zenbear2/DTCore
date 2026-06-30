`timescale 1 ns / 1 ps

module IFB #(
    parameter DWIDTH = 128,
    parameter ADDR_WIDTH = 9
)(
    input                      clk,
    input                      rst_n,
    input                      ifb_wr_en,
    input  wire [3:0]          ifb_rd_en,      // FWFT Ack
    input  wire [DWIDTH-1:0]   ifb_din,
    input                      ifb_din_valid,
    output wire [DWIDTH-1:0]   ifb_dout,       // FWFT Data
    output wire                ifb_empty,      
    output wire                ifb_full,
    output wire [3:0]          ifb_dout_valid  // FWFT Valid
);

    localparam SUB_DWIDTH   = 32;
    localparam NUM_SUB_FIFO = DWIDTH / SUB_DWIDTH;

    wire [NUM_SUB_FIFO-1:0] sub_fifo_full;
    wire [NUM_SUB_FIFO-1:0] sub_fifo_valid; // 用來收集每個 Sub-FIFO 的 valid

    // 連接 output valid
    assign ifb_dout_valid = sub_fifo_valid;

    genvar i;
    generate
        for (i = 0; i < NUM_SUB_FIFO; i = i + 1) begin : gen_sub_fifo
            
            // 使用 XPM FWFT FIFO
            x_fwft_fifo #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DWIDTH    (SUB_DWIDTH)
            ) x_fwft_inst (
                .clk        (clk),
                .rst_n      (rst_n),
                
                // Write
                .wr_en      (ifb_wr_en & ifb_din_valid),
                .din        (ifb_din[i*SUB_DWIDTH +: SUB_DWIDTH]),
                .full       (sub_fifo_full[i]),
                
                // Read (FWFT)
                .rd_en      (ifb_rd_en[i]),
                .dout       (ifb_dout[i*SUB_DWIDTH +: SUB_DWIDTH]),
                .empty      (), // 這裡我們主要看 valid
                .data_valid (sub_fifo_valid[i])
            );

        end
    endgenerate

    // Aggregate Signals
    assign ifb_full  = |sub_fifo_full;
    
    // Empty 邏輯：只要有任何一個 channel 沒有 valid 資料，對 Core 來說就是 empty
    assign ifb_empty = |(~sub_fifo_valid);

endmodule