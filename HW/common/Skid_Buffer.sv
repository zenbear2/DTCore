`timescale 1 ns / 1 ps

module skid_buffer #(
    parameter DWIDTH = 128
)(
    input  wire              clk,
    input  wire              rst_n,

    // Slave Interface (來自上游，例如 ODB FIFO)
    input  wire              s_valid,
    output wire              s_ready,
    input  wire [DWIDTH-1:0] s_data,

    // Master Interface (往下游，例如 DMA 或 外部介面)
    output wire              m_valid,
    input  wire              m_ready,
    output wire [DWIDTH-1:0] m_data
);

    // 內部狀態
    reg [DWIDTH-1:0] data_buffer;
    reg              data_buffer_valid;
    
    // 邏輯說明：
    // 當 Skid Buffer 本身有空間 (buffer 無效) 或者 下游準備好接收 (m_ready) 時，
    // 我們就可以告訴上游我們準備好了。
    assign s_ready = !data_buffer_valid || m_ready;

    // 輸出邏輯：
    // 如果 Buffer 有資料，優先輸出 Buffer 的資料。
    // 如果 Buffer 沒資料，直接 Pass-through 上游的資料。
    assign m_valid = data_buffer_valid ? 1'b1 : s_valid;
    assign m_data  = data_buffer_valid ? data_buffer : s_data;

    always @(posedge clk) begin
        if (!rst_n) begin
            data_buffer_valid <= 1'b0;
            data_buffer       <= {DWIDTH{1'b0}};
        end else begin
            // 狀態機邏輯：
            // 當下游還沒準備好 (m_ready=0)，但上游送來了有效資料 (s_valid=1)
            // 且我們當前 Buffer 是空的，這時候就要發生 "Skid" (滑動/暫存)
            if (m_ready == 1'b0 && s_valid == 1'b1 && data_buffer_valid == 1'b0) begin
                data_buffer       <= s_data;
                data_buffer_valid <= 1'b1;
            end
            // 當下游準備好接收 (m_ready=1)，Buffer 裡的資料被收走了，狀態清除
            else if (m_ready == 1'b1) begin
                data_buffer_valid <= 1'b0;
            end
        end
    end

endmodule