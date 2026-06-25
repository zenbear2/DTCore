`timescale 1 ns / 1 ps

module IDB #(
    parameter IDB_INST = 4,
    parameter SEL_WIDTH = 2,
    parameter DWIDTH = 128
)(
    input                     clk,
    input                     rst_n,
    
    // 寫入控制 (來自 CSR/AXI)
    input                     idb_wr_sel_en_n,
    input  wire[SEL_WIDTH-1:0]idb_wr_sel,
    input  wire[DWIDTH-1:0]   idb_din,
    input  wire               idb_din_valid,
    
    // 讀取控制
    input  wire[IDB_INST-1:0] core_req,    // [新增] 來自 DTCore 的讀取請求 (Normal Operation)
    input  wire[IDB_INST-1:0] idb_rd_en,   // 來自 CSR 的讀取請求 (Debug/External)
    
    // 輸出狀態
    output wire[DWIDTH-1:0]   idb_dout   [IDB_INST-1:0],
    output wire[IDB_INST-1:0] idb_empty,
    output wire[IDB_INST-1:0] idb_full,
    output wire[IDB_INST-1:0] idb_dout_valid
);

    reg [IDB_INST-1:0] wr_en;

    // 寫入解碼邏輯 (保持不變)
    always @(*)begin
        case({idb_din_valid,idb_wr_sel_en_n,idb_wr_sel})
            4'b1000: wr_en = 4'b0001;
            4'b1001: wr_en = 4'b0010;
            4'b1010: wr_en = 4'b0100;
            4'b1011: wr_en = 4'b1000;
            default: wr_en = 4'b0000;
        endcase
    end

    genvar i;
    generate
    for(i=0; i<IDB_INST; i=i+1) begin : gen_idb_fifo

        // 整合讀取訊號：Core 請求 或 CSR 請求 都能觸發讀取
        wire fifo_pop;
        assign fifo_pop = core_req[i] | idb_rd_en[i];

        // 使用 XPM FWFT FIFO (Latency 2, Stable)
        x_fwft_fifo #(
            .ADDR_WIDTH(9),
            .DWIDTH(DWIDTH)
        ) x_fwft_inst (
            .clk        (clk),
            .rst_n      (rst_n),
            
            // 寫入端
            .wr_en      (wr_en[i]),
            .din        (idb_din),
            .full       (idb_full[i]),

            // 讀取端 (FWFT Mode)
            // rd_en 在這裡是 "Ack/Pop"，告訴 FIFO 當前資料已使用，請換下一筆
            .rd_en      (fifo_pop), 
            
            .dout       (idb_dout[i]),
            .empty      (idb_empty[i]),
            .data_valid (idb_dout_valid[i])
        );

    end
    endgenerate

endmodule