`timescale 1 ns / 1 ps

module fifo_sync #(
    parameter ADDR_WIDTH = 2,
    parameter DWIDTH     = 128
)
(
    input                   rst_n,
    input                   clk,
    input                   wr_en,
    input                   rd_en,
    input  wire[DWIDTH-1:0] din,
    output reg [DWIDTH-1:0] dout,
    output                  empty,
    output                  full,
    output reg              data_valid
);

  localparam DEPTH = 1 << ADDR_WIDTH; 

  reg [DWIDTH-1:0] fifo [0:DEPTH-1];
  
  reg [ADDR_WIDTH:0] wptr, rptr; 
  
  wire [ADDR_WIDTH-1:0] waddr = wptr[ADDR_WIDTH-1:0];
  wire [ADDR_WIDTH-1:0] raddr = rptr[ADDR_WIDTH-1:0];

  assign empty = (wptr == rptr);

  assign full  = (wptr[ADDR_WIDTH] != rptr[ADDR_WIDTH]) && 
                 (wptr[ADDR_WIDTH-1:0] == rptr[ADDR_WIDTH-1:0]);

  wire valid_wr = wr_en && (!full || rd_en);
  wire valid_rd = rd_en && !empty;


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
  // Read Logic
  // --------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) begin
      rptr <= 0;
      data_valid <= 0;
    end else if (valid_rd) begin
      dout <= fifo[raddr];
      rptr <= rptr + 1'b1;
      data_valid <= 1;
    end else begin
      data_valid <= 0;
    end
  end


endmodule