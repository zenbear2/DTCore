`timescale 1 ns / 1 ps

module x_fwft_fifo #(
    parameter ADDR_WIDTH = 9,
    parameter DWIDTH     = 128
)(
    input  wire              clk,
    input  wire              rst_n,      // Active Low Reset
    
    // Write Interface
    input  wire              wr_en,
    input  wire [DWIDTH-1:0] din,
    output wire              full,
    
    // FWFT Read Interface
    input  wire              rd_en,      
    output wire [DWIDTH-1:0] dout,       
    output wire              empty,      
    output wire              data_valid  
);

    // 參數轉換
    localparam FIFO_DEPTH = 1 << ADDR_WIDTH;

    // 內部訊號
    wire rst_p = ~rst_n; // XPM 需要 Active High Reset
    wire wr_rst_busy;
    wire rd_rst_busy;

    // ----------------------------------------------------------------------
    // 安全保護 (Safety Logic)
    // ----------------------------------------------------------------------
    wire safe_wr_en = wr_en && (!wr_rst_busy);
    wire safe_rd_en = rd_en && (!rd_rst_busy);

    // ----------------------------------------------------------------------
    // XPM Instantiation (FWFT Mode)
    // ----------------------------------------------------------------------
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE    ("auto"),
        .FIFO_WRITE_DEPTH    (FIFO_DEPTH),
        .WRITE_DATA_WIDTH    (DWIDTH),
        .READ_DATA_WIDTH     (DWIDTH),
        
        // --- FWFT 關鍵設定 ---
        .READ_MODE           ("fwft"),    
        .FIFO_READ_LATENCY   (0),         

        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),  // 不使用 ECC
        .USE_ADV_FEATURES    ("1000")     // Bit 12 Enable data_valid
    ) xpm_fwft_inst (
        .rst        (rst_p),
        .wr_clk     (clk),
        
        // Write Port
        .wr_en      (safe_wr_en),
        .din        (din),
        .full       (full),
        .wr_rst_busy(wr_rst_busy),

        // Read Port (FWFT)
        .rd_en      (safe_rd_en),  
        .dout       (dout),        
        .empty      (empty),
        .data_valid (data_valid),
        .rd_rst_busy(rd_rst_busy),

        // Unused ports (已移除 ECC 相關 port 以避免 Syntax Error)
        .sleep      (1'b0),
        .overflow   (),
        .underflow  (),
        .prog_full  (),
        .prog_empty (),
        .wr_data_count(),
        .rd_data_count()
        // 移除 injectsbit, injectdbit, sbiterr, dbiterr
    );

endmodule