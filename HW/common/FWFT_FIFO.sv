`timescale 1 ns / 1 ps

module fwft_fifo #(
    parameter ADDR_WIDTH = 4,
    parameter DWIDTH     = 128
)
(
    input                   rst_n,
    input                   clk,
    input                   wr_en,
    input                   rd_en,
    input  wire[DWIDTH-1:0] din,
    output wire[DWIDTH-1:0] dout,
    output                  empty,
    output                  full,
    output                  data_valid
);

  localparam DEPTH = 1 << ADDR_WIDTH;


  reg [DWIDTH-1:0] fifo [0:DEPTH-1];
  
  reg [ADDR_WIDTH:0] wptr;
  reg [ADDR_WIDTH:0] rptr;

  wire [ADDR_WIDTH-1:0] waddr = wptr[ADDR_WIDTH-1:0];
  wire [ADDR_WIDTH-1:0] raddr = rptr[ADDR_WIDTH-1:0];

  // --------------------------------------------------------
  // Status Flags (Pointer Comparison)
  // --------------------------------------------------------
  assign empty = (wptr == rptr);
  
  assign full  = (wptr[ADDR_WIDTH] != rptr[ADDR_WIDTH]) && 
                 (wptr[ADDR_WIDTH-1:0] == rptr[ADDR_WIDTH-1:0]);

  assign data_valid = !empty;

  wire valid_wr = wr_en && !full;
  wire valid_rd = rd_en && !empty;

  // --------------------------------------------------------
  // FWFT Output Logic (Asynchronous Read -> LUTRAM)
  // --------------------------------------------------------
  assign dout = fifo[raddr];

  // --------------------------------------------------------
  // Write Logic
  // --------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) begin
      wptr <= 0;
    end else if (valid_wr) begin
      fifo[waddr] <= din;
      wptr <= wptr + 1'b1;
    end
  end

  // --------------------------------------------------------
  // Read Logic (Pointer Update Only)
  // --------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) begin
      rptr <= 0;
    end else if (valid_rd) begin
      rptr <= rptr + 1'b1;
    end
  end

endmodule