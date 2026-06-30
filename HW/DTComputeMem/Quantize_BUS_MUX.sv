module Quantize_BUS_MUX #(
    parameter I_DATA_WIDTH = 64,       // High(32) + Low(32) 來自 PE
    parameter DATA_SCALE_WIDTH = 48,   // 32(High) + 16(Shift)
    parameter NUM_IN_PORTS = 4
) (
    input wire clk,
    input wire rst_n,

    // 注意：不需要 i_scale 了，因為 PE 已經補償過
    input wire [I_DATA_WIDTH*NUM_IN_PORTS-1:0] i_data,
    input wire [NUM_IN_PORTS-1:0] i_data_valid,

    input wire [$clog2(NUM_IN_PORTS)-1:0] i_select,
    input wire i_select_valid,

    output reg [I_DATA_WIDTH/2-1:0]   o_shifted_result, // 32-bit 最終輸出
    output reg o_data_valid
);

    localparam HALF_WIDTH = I_DATA_WIDTH / 2; // 32
    localparam SHIFT_BITS = 16;               // 修正：位移量為 16

    // 1. 選擇輸入
    wire [I_DATA_WIDTH-1:0] selected_data;
    wire selected_valid;
    
    assign selected_data  = i_data[i_select*I_DATA_WIDTH +: I_DATA_WIDTH];
    assign selected_valid = i_data_valid[i_select];

    // 2. 拆分 PE 的輸出 (已經經過 PE 內部補償)
    // prod_high: 來自 PE 的 o_scale_acc_up
    // prod_low : 來自 PE 的 o_scale_acc_down
    wire signed [HALF_WIDTH-1:0] prod_high = selected_data[I_DATA_WIDTH-1 : HALF_WIDTH];
    wire signed [HALF_WIDTH-1:0] prod_low  = selected_data[HALF_WIDTH-1 : 0];

    // 3. 重建 (Reconstruction)
    // 公式: Total = (prod_high * 2^16) + prod_low
    // 這裡我們將 prod_high 左移 16 位，並與 Sign-Extended 的 prod_low 相加
    wire signed [DATA_SCALE_WIDTH-1:0] full_sum;
    
    // {prod_high, 16'b0} + {{16{prod_low[31]}}, prod_low}
    assign full_sum = {prod_high, {SHIFT_BITS{1'b0}}} + {{16{prod_low[31]}}, prod_low};

    // 4. Rounding (四捨五入)
    // 加 0.5 (即 bit 15 為 1)，然後右移 16
    wire signed [HALF_WIDTH-1:0] final_result;
    assign final_result = (full_sum + (32'd1 << (SHIFT_BITS - 1))) >>> SHIFT_BITS;

    // 5. 輸出暫存
    always @(posedge clk) begin
        if (i_select_valid) begin
            o_shifted_result <= final_result;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            o_data_valid <= 1'b0;
        end else begin
            o_data_valid <= i_select_valid & selected_valid;
        end
    end    

endmodule