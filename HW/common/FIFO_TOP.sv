`timescale 1 ns / 1 ps

module fifo_sync_timing_opt #(
    parameter ADDR_WIDTH = 2,
    parameter DWIDTH     = 128,
    // 新增參數：保留多少空間以應對 Full 信號的延遲
    // 設定為 2 是最安全的 (1 cycle for reg, 1 cycle for logic/skid)
    parameter FULL_MARGIN = 2 
)
(
    input                   rst_n,
    input                   clk,
    input                   wr_en,
    input                   rd_en,
    input  wire[DWIDTH-1:0] din,
    output reg [DWIDTH-1:0] dout,
    output wire             empty, // Empty 通常保留組合邏輯以免影響讀取延遲
    output reg              full,  // [修改] 改為 Reg 輸出，切斷 Timing Path
    output reg              data_valid
);

  localparam DEPTH = 1 << ADDR_WIDTH;

  reg [DWIDTH-1:0] fifo [0:DEPTH-1];
  
  reg [ADDR_WIDTH:0] wptr, rptr; 
  
  wire [ADDR_WIDTH-1:0] waddr = wptr[ADDR_WIDTH-1:0];
  wire [ADDR_WIDTH-1:0] raddr = rptr[ADDR_WIDTH-1:0];

  // --------------------------------------------------------
  // Helper Logic
  // --------------------------------------------------------
  // 為了產生 Register Full，我們需要一個計數器或預判邏輯
  // 使用 Up/Down Counter 是最直觀且時序好的方法
  reg [ADDR_WIDTH:0] cnt; 

  assign empty = (cnt == 0); // Empty 可以依賴 Counter
  
  // Full 邏輯的輸入條件 (Combinational)
  // 當目前的數量 >= (總深度 - 保留空間) 時，視為將滿
  wire full_comb = (cnt >= (DEPTH - FULL_MARGIN));

  wire valid_wr = wr_en && !full; // 注意：這裡使用 Registered Full 來阻擋寫入
  wire valid_rd = rd_en && !empty;

  // --------------------------------------------------------
  // FIFO Operation
  // --------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) begin
      wptr <= 0;
      rptr <= 0;
      cnt  <= 0;
      full <= 1'b0; // Reset Full
      data_valid <= 0;
    end else begin
      // 1. Write Pointer
      if (valid_wr) begin
        fifo[waddr] <= din;
        wptr <= wptr + 1'b1;
      end

      // 2. Read Pointer & Data
      if (valid_rd) begin
        dout <= fifo[raddr];
        rptr <= rptr + 1'b1;
        data_valid <= 1;
      end else begin
        data_valid <= 0;
      end

      // 3. Counter Update (Track usage)
      case ({valid_wr, valid_rd})
        2'b10: cnt <= cnt + 1; // Write only
        2'b01: cnt <= cnt - 1; // Read only
        default: cnt <= cnt;   // Both or neither
      endcase

      // 4. [關鍵修改] Register Full Signal
      // 利用 Counter 判斷，並鎖存結果。
      // 這將 wptr/cnt 到外部邏輯的路徑切斷了。
      full <= full_comb; 
    end
  end

endmodule