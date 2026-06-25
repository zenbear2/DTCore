`timescale 1 ns / 1 ps

module pipeline_register_slice #(
    parameter DWIDTH = 128
)(
    input  wire              clk,
    input  wire              rst_n,

    // Slave Interface (來自 DTCore)
    input  wire              s_valid,
    output wire              s_ready,
    input  wire [DWIDTH-1:0] s_data,

    // Master Interface (往 ODB)
    output reg               m_valid,
    input  wire              m_ready,
    output reg  [DWIDTH-1:0] m_data
);

    // 內部狀態
    reg [DWIDTH-1:0] skid_data;
    reg              skid_valid;

    // -------------------------------------------------------
    // 邏輯說明：
    // 我們使用兩個暫存器：
    // 1. m_data (主輸出暫存器)
    // 2. skid_data (備用/滑動暫存器)
    //
    // 這樣做是為了保證 "Pipeline" 行為：
    // 當 m_data 有資料且下游 (m_ready) 還沒收走時，
    // 我們依然可以接收上游的一筆新資料存入 skid_data (s_ready 依然為 High)。
    // 這避免了單純加 Register 造成的 "Bubble" (頻寬減半) 問題。
    // -------------------------------------------------------

    // 當 Skid Buffer 是空的，我們就可以接收新資料
    assign s_ready = !skid_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            m_valid    <= 1'b0;
            m_data     <= {DWIDTH{1'b0}};
            skid_valid <= 1'b0;
            skid_data  <= {DWIDTH{1'b0}};
        end else begin
            // ---------------------------------------------
            // Main Output Register (m_data/m_valid) 控制
            // ---------------------------------------------
            if (m_ready || !m_valid) begin
                // 下游準備好接收，或者我們當前是空的：可以更新輸出
                if (skid_valid) begin
                    // 優先從 Skid Buffer 搬資料出去
                    m_valid    <= 1'b1;
                    m_data     <= skid_data;
                    skid_valid <= 1'b0; // Skid 搬空了
                    
                    // 如果同時上游也有新資料進來，直接補進 Skid (Corner Case)
                    if (s_valid && s_ready) begin
                        skid_valid <= 1'b1;
                        skid_data  <= s_data;
                    end
                end else if (s_valid) begin
                    // Skid 是空的，直接把上游資料 Pass 到輸出暫存器
                    m_valid <= 1'b1;
                    m_data  <= s_data;
                end else begin
                    // 沒資料了
                    m_valid <= 1'b0;
                end
            end 
            
            // ---------------------------------------------
            // Skid Register (skid_data/skid_valid) 控制
            // ---------------------------------------------
            // 當輸出暫存器 (m_data) 被卡住 (!m_ready && m_valid)，
            // 且 Skid 是空的，我們就把上游新資料存入 Skid
            else if (s_valid && s_ready) begin
                skid_valid <= 1'b1;
                skid_data  <= s_data;
            end
        end
    end

endmodule