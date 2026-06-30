module index_counter #(
    parameter THREAD_ID_WIDTH = 2,
    parameter CALC_LATENCY    = 4  
)(
    input wire clk,
    input wire rst_n,
    // ... (Inputs 保持不變)
    input wire i_tile_enable,
    input wire [3:0] i_mode,
    input wire i_act_tile_valid,
    input wire i_weight_tile_valid,
    input wire [THREAD_ID_WIDTH-1:0] i_tile_act_thread_id,
    input wire [THREAD_ID_WIDTH-1:0] i_tile_weight_thread_id,
    input wire [THREAD_ID_WIDTH-1:0] i_data_act_thread_id,
    input wire [THREAD_ID_WIDTH-1:0] i_data_weight_thread_id,

    // ... (Outputs 保持不變)
    output reg [1:0]  o_index_counter,   // 改為 reg 輸出
    output wire       o_act_put_data,
    output wire       o_weight_put_data, 
    output reg        o_pe_enable,       // 改為 reg 輸出
    output reg        o_tile_busy        // 改為 reg 輸出
);

    // 1. 基本定義
    localparam SCALE_MODE = 2'b10;
    wire [1:0] compute_mode = i_mode[1:0];
    wire [1:0] sparse_mode  = i_mode[3:2]; 
    wire       is_scale_mode = (compute_mode == SCALE_MODE);

    // 2. 狀態與計數器
    reg [4:0] state_cnt;
    wire      is_active = state_cnt[4];
    wire [3:0] timer    = state_cnt[3:0];

    // ====================================================================
    // 優化重點 A: 邊界值快取 (Shadow Register)
    // ====================================================================
    // 原本的寫法需要在每個 Cycle 做加法與 Mux，現在我們用 FF 存起來
    // 只有在 IDLE (準備啟動時) 更新這個 Cache，運行中直接讀取 FF
    reg [3:0] r_limit_cache;
    reg [3:0] r_end_val_cache;

    // 組合邏輯算出當前的參數 (不在 Critical Path 上，因為下個 Cycle 才用)
    wire [3:0] w_curr_limit = is_scale_mode ? 4'd1 : {2'b00, sparse_mode};
    wire [4:0] w_curr_end   = {1'b0, w_curr_limit} + CALC_LATENCY; // 加法在這裡做

    always @(posedge clk) begin
        if (!is_active) begin 
            // 當不在 Active 時，預先鎖存下一次任務的參數
            r_limit_cache   <= w_curr_limit;
            r_end_val_cache <= w_curr_end[3:0];
        end
        // Active 期間保持不變，這樣比較器只需要跟 FF 比，不需要跟加法器比
    end

    // ====================================================================
    // 優化重點 B: Trigger 邏輯與 Lock (保持原邏輯，但路徑變短)
    // ====================================================================
    reg scale_lock;
    // 使用 Cached 的值來判斷結束，速度更快
    wire is_scale_finishing = is_active && is_scale_mode && (timer == r_end_val_cache);

    always @(posedge clk) begin
        if (!rst_n)             scale_lock <= 1'b0;
        else if (!is_scale_mode) scale_lock <= 1'b0;
        else if (is_scale_finishing) scale_lock <= 1'b1;
    end

    wire act_id_match    = (i_tile_act_thread_id == i_data_act_thread_id) && i_act_tile_valid;
    wire weight_id_match = (i_tile_weight_thread_id == i_data_weight_thread_id) && i_weight_tile_valid;
    wire ready_cond      = is_scale_mode ? !scale_lock : (act_id_match && weight_id_match);
    wire trigger_req     = i_tile_enable && ready_cond;

    // ====================================================================
    // 優化重點 C: 並行 Next State 計算 (Parallel Execution)
    // ====================================================================
    // 預先算出「如果沒有 Trigger」會變成的狀態
    reg [4:0] nx_state_default;
    
    always @(*) begin
        if (is_active) begin
            if (timer == r_end_val_cache)
                nx_state_default = 5'b0_0000; // Done -> IDLE
            else
                nx_state_default = state_cnt + 1'b1; // Continue
        end else begin
            nx_state_default = 5'b0_0000; // Stay IDLE
        end
    end

    // 判斷是否允許重啟 (使用 Cached Limit)
    wire allow_restart = is_active && (timer >= r_limit_cache) && (!is_scale_mode);
    wire can_start     = (!is_active || allow_restart);

    // 最終 Next State Mux：只在最後一級看 trigger_req
    // 這樣 trigger_req (包含 ID 比較) 的延遲只影響最後一級 Mux
    reg [4:0] nx_state_final;
    always @(*) begin
        if (trigger_req && can_start)
            nx_state_final = 5'b1_0000; // Jump to Start
        else
            nx_state_final = nx_state_default; // Use pre-calculated default
    end

    // 更新狀態
    always @(posedge clk) begin
        if (!rst_n) state_cnt <= 5'b0_0000;
        else        state_cnt <= nx_state_final;
    end

    // ====================================================================
    // 優化重點 D: 輸出暫存 (Registered Outputs)
    // ====================================================================
    // 為了不增加 Latency，我們必須「預判」輸出。
    // 由於我們上面已經算出了 nx_state_final (下個 Cycle 的狀態)，
    // 我們可以直接解碼 nx_state_final 來決定輸出的值，這樣輸出就是 Registered 的。
    
    always @(posedge clk) begin
        if (!rst_n) begin
            o_tile_busy     <= 1'b0;
            o_index_counter <= 2'b00;
            o_pe_enable     <= 1'b0;
        end else begin
            // 直接根據 "下個狀態" 更新輸出 FF
            o_tile_busy     <= nx_state_final[4]; // Bit 4 is is_active
            o_index_counter <= nx_state_final[1:0]; 
            
            // PE Enable 邏輯：Active 且 Timer <= Limit
            // 這裡稍微複雜，因為我們存的是 "Next State"。
            // 由於 Limit 是常數(Cache)，我們可以檢查 Next Timer 是否在範圍內。
            // 注意：nx_state_final 已經包含了跳轉邏輯
            o_pe_enable     <= nx_state_final[4] && (nx_state_final[3:0] <= r_limit_cache);
        end
    end

    // Put Data 比較難完全 Register 化而不增加 Latency，因為它直接相依於 trigger_req (當下的 Input)。
    // 但我們可以優化 Ready Slot 的判斷
    wire is_ready_slot = (!is_active) || (timer >= r_limit_cache);
    assign o_act_put_data    = (!is_scale_mode) && trigger_req && is_ready_slot;
    assign o_weight_put_data = o_act_put_data;

endmodule