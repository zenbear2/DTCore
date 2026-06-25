module Quantize_Reorder_Buffer #(
    parameter I_DATA_WIDTH = 32,
    parameter O_DATA_WIDTH = 8,
    parameter NUM_IN_PORTS = 4,
    // parameter ZERO_POINT_WIDTH = 8, // [移除] 對稱量化不需要 ZP 寬度參數
    parameter IS_UINT8 = 0 // 0: INT8 (-128~127), 1: UINT8 (0~255)
) (
    input wire clk,
    input wire rst_n,

    input wire [I_DATA_WIDTH*NUM_IN_PORTS-1:0] i_data,
    input wire i_data_valid, 

    // input wire [ZERO_POINT_WIDTH-1:0] i_zero_point, // [移除] 移除 ZP 輸入埠

    input wire i_relu_valid,

    input wire [$clog2(NUM_IN_PORTS)-1:0] i_select,
    input wire i_select_valid,

    output reg [O_DATA_WIDTH-1:0] o_data,
    output reg o_data_valid
);

    // 定義飽和範圍 (Compile-time Constants)
    // 對稱量化通常使用 INT8 (-128 ~ 127) 或 (-127 ~ 127)
    localparam signed [31:0] MAX_VAL = IS_UINT8 ? 32'd255 : 32'd127;
    localparam signed [31:0] MIN_VAL = IS_UINT8 ? 32'd0   : -32'd128;

    // 1. 選擇數據
    wire signed [I_DATA_WIDTH-1:0] selected_data;
    assign selected_data = i_data[i_select*I_DATA_WIDTH +: I_DATA_WIDTH];

    // 2. [移除] 加上 Zero Point 的步驟
    // 對稱量化下，數值直接通過，不需要加法器。
    // wire signed [I_DATA_WIDTH:0] val_with_zp;
    // assign val_with_zp = ...

    // 3. 飽和 (Saturation) 與 ReLU 邏輯
    reg [O_DATA_WIDTH-1:0] final_val;

    always @(*) begin
        // 直接使用選中的數據進行判斷
        reg signed [I_DATA_WIDTH-1:0] temp;
        temp = selected_data; 

        // Apply ReLU (if valid)
        // 若開啟 ReLU，負數直接歸零
        if (i_relu_valid && (temp < 0)) begin
             temp = 0;
        end

        // Apply Max/Min Clamp (飽和截斷)
        // 檢查是否超過 8-bit (或 O_DATA_WIDTH) 的表示範圍
        if (temp > MAX_VAL) 
            final_val = MAX_VAL[O_DATA_WIDTH-1:0];
        else if (temp < MIN_VAL)
            final_val = MIN_VAL[O_DATA_WIDTH-1:0];
        else
            final_val = temp[O_DATA_WIDTH-1:0];
    end

    // 4. 輸出暫存
    always @(posedge clk) begin
        if (i_select_valid) begin
            o_data <= final_val;
        end
    end

    // Valid 訊號處理
    always @(posedge clk) begin
        if (!rst_n) begin
            o_data_valid <= 1'b0;
        end else begin
            if (i_select_valid) begin
                o_data_valid <= i_data_valid; // 這裡可能需要根據您的系統邏輯調整 (是否需要 selected_valid)
            end else begin
                o_data_valid <= 1'b0;
            end
        end
    end    

endmodule