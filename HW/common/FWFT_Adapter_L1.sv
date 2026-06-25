`timescale 1 ns / 1 ps

// 加入 hierarchy 屬性，防止模組邊界被打散消失
(* keep_hierarchy = "yes" *) 
module fwft_adapter_latency1 #(
    parameter DWIDTH = 128
)(
    input  wire              clk,
    input  wire              rst_n,

    // FIFO Interface
    input  wire              fifo_empty,
    input  wire [DWIDTH-1:0] fifo_dout,     
    output wire              fifo_rd_en,    

    // FWFT Interface
    output wire              fwft_valid,    
    input  wire              fwft_ready,    
    output wire [DWIDTH-1:0] fwft_data      
);

    // -----------------------------------------------------------
    // 抗優化屬性 (Attributes to prevent optimization)
    // -----------------------------------------------------------
    (* keep = "true" *) reg              dout_valid;     // 強制保留
    (* keep = "true" *) reg [DWIDTH-1:0] dout_reg;       // 強制保留 Skid Buffer
    (* keep = "true" *) reg              dout_reg_valid; // 強制保留狀態位

    // -----------------------------------------------------------
    // 讀取控制邏輯
    // -----------------------------------------------------------
    // 下游準備好 (fwft_ready) 或 內部暫存器是空的 (!dout_reg_valid) 時，我們就可以從 FIFO 預讀
    assign fifo_rd_en = !fifo_empty && (!dout_reg_valid || fwft_ready);

    // -----------------------------------------------------------
    // 狀態機 (修正 sensitivity list)
    // -----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin // <--- 修正：加入 negedge rst_n
        if (!rst_n) begin
            dout_valid     <= 1'b0;
            dout_reg_valid <= 1'b0;
            dout_reg       <= {DWIDTH{1'b0}};
        end else begin
            // 1. 處理 FIFO 讀取延遲 (Latency 1)
            if (fifo_rd_en) 
                dout_valid <= 1'b1;
            else if (fwft_ready || (dout_valid && !dout_reg_valid)) 
                dout_valid <= 1'b0;

            // 2. 處理 Skid/暫存
            // 當 FIFO 輸出有效(dout_valid)，但下游還沒拿走(!fwft_ready)，
            // 且 Skid Buffer 是空的(!dout_reg_valid)，這時必須存起來
            if (dout_valid && !fwft_ready && !dout_reg_valid) begin
                dout_reg       <= fifo_dout;
                dout_reg_valid <= 1'b1;
                dout_valid     <= 1'b0; // 數據移入 Reg，原通道視為空
            end else if (fwft_ready) begin
                // 下游拿走了數據 (如果下游拿走的是 dout_reg 的數據)
                dout_reg_valid <= 1'b0;
            end
        end
    end

    // -----------------------------------------------------------
    // 輸出邏輯 MUX (Critical Path 所在)
    // -----------------------------------------------------------
    // 使用 keep 屬性保護這個 Mux 的輸出結果不被過度合併
    (* keep = "true" *) wire mux_valid_out;
    (* keep = "true" *) wire [DWIDTH-1:0] mux_data_out;

    assign mux_valid_out = dout_reg_valid || dout_valid;
    assign mux_data_out  = dout_reg_valid ? dout_reg : fifo_dout;

    assign fwft_valid = mux_valid_out;
    assign fwft_data  = mux_data_out;

endmodule