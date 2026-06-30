module FetchDecodeUnit #(
    parameter DWIDTH = 32 // 固定為 32-bit
)(
    input  wire              clk,
    input  wire              rst_n,

    // --- 上游: 單一 Slice 的 FIFO 介面 ---
    input  wire              i_fifo_empty,
    input  wire [31:0]       i_fifo_data,  // 32-bit input
    input  wire              i_fifo_valid,
    output wire              o_fifo_rd_en,

    // --- 下游: Hazard/Stall Control ---
    // Sub Slot Stall from Barrrier
    input  wire              i_backend_stall,
    
    // SubDecoder Outputs (單一 bit)
    output reg               o_regfile_tile_wb_op,
    output reg               o_regfile_core_in_op,
    output reg               o_regfile_read_op,
    output reg               o_block_sync_op,
    output wire               o_tile_mode_op,
    output wire               o_tile_en_op,
    output wire               o_tile_wb_op,
    output wire               o_core_out_op,
    output wire               o_error_op,

    // Parsed Data Fields (解析後的欄位)
    // 依照 DTController 中的 Bit Map 進行切分
    output reg [5:0]         o_opcode,
    
    // RFBPCtrl 相關
    output reg [11:0]        o_rf_src_sel,   // [11:0]
    output reg [9:0]         o_addr,         // [9:0]
    output reg [9:0]         o_len,          // [19:10]
    output reg [1:0]         o_agu_mode,     // [21:20]
    output reg [1:0]         o_thread_id,    // [23:22]
    
    // Core Output Ctrl 相關
    output reg [1:0]         o_core_out_sel, // [1:0]
    output reg               o_core_out_val, // [2]
    output reg [1:0]         o_core_out_tid, // [4:3]

    // Tile State 相關
    output reg               o_tile_act_sel, // [0]
    output reg [1:0]         o_tile_act_tid, // [4:3]
    output reg               o_tile_w_sel,   // [5]
    output reg [1:0]         o_tile_w_tid,   // [9:8]
    output reg [3:0]         o_tile_mode,    // [13:10]
    output reg               o_tile_relu,    // [14]
    output reg               o_tile_clr_acc, // [15]
    output reg               o_tile_clr_out, // [16]
    output reg [15:0]        o_tile_scale,   // [15:0]
    output reg [7:0]         o_tile_zp,      // [23:16]

    // Tile WB 相關
    output reg [9:0]         o_wb_addr,      // [9:0] (共用 o_addr)
    output reg [7:0]         o_wb_reorder,   // [17:10]
    output reg [7:0]         o_wb_dabus,     // [25:18]
    output reg [3:0]         o_wb_mask,      // [29:26]

    // Barrier 相關
    output reg [4:0]         o_sync_req,     // [4:0]
    output reg [1:0]         o_agu_wait,     // [6:5]
    output reg               o_tile_wait,    // [7]
    output reg [5:0]         o_status        // [13:8]
);

    // ============================================================
    // Stage 1: 32-bit Skid Buffer
    // ============================================================
    reg [31:0] main_buffer;
    reg        main_valid;
    reg [31:0] skid_buffer;
    reg        skid_valid;

    // 邏輯與之前完全相同，只是寬度變為 32-bit
    wire sb_ready = !i_backend_stall;
    assign o_fifo_rd_en = (sb_ready || !skid_valid) && i_fifo_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            main_valid  <= 1'b0;
            skid_valid  <= 1'b0;
            main_buffer <= 32'd0;
            skid_buffer <= 32'd0;
        end else begin
            // -------------------------------------------------------
            // 1. 下游取走 (Downstream Consume)
            // -------------------------------------------------------
            if (sb_ready) begin
                if (skid_valid) begin
                    main_buffer <= skid_buffer;
                    main_valid  <= 1'b1;
                    skid_valid  <= 1'b0;
                end else begin
                    // Skid 是空的，如果沒有新資料進來，Main 就變無效
                    // 注意：這裡先預設無效，下面第2步如果有資料進來會覆蓋成有效
                    main_valid <= 1'b0; 
                end
            end

            // -------------------------------------------------------
            // 2. 上游寫入 (Upstream Produce) - [關鍵修正]
            // -------------------------------------------------------
            // 必須使用 i_fifo_valid (代表 BRAM 資料真的到了)
            // 而不是 o_fifo_rd_en (代表我發出了請求)
            if (i_fifo_valid) begin
                if (sb_ready && !skid_valid) begin
                    // Case A: 正常流動 (Pipeline flowing)
                    // Skid 空，且後端準備好接收 -> 直接寫入 Main Buffer
                    // (覆蓋掉上面第1步可能的 main_valid <= 0)
                    main_buffer <= i_fifo_data;
                    main_valid  <= 1'b1;
                end else if (sb_ready && skid_valid) begin
                     // Case B: 這是不可能的狀態 (sb_ready=1 會清空 skid)，但為了邏輯完整性：
                     // Skid 遞補到 Main，新資料補進 Skid
                     main_buffer <= skid_buffer; // 這一行其實在第1步做過了
                     skid_buffer <= i_fifo_data;
                     skid_valid  <= 1'b1;
                     main_valid  <= 1'b1;
                end else if (!sb_ready) begin
                    // Case C: 後端忙碌 (Backpressure)
                    // 如果 Main 滿了，填入 Skid
                    if (main_valid) begin
                        if (!skid_valid) begin
                            skid_buffer <= i_fifo_data;
                            skid_valid  <= 1'b1;
                        end
                    end else begin
                        // Main 剛好是空的 (罕見但可能)，直接填 Main
                        main_buffer <= i_fifo_data;
                        main_valid  <= 1'b1;
                    end
                end
            end
        end
    end

    // ============================================================
    // Stage 2: Decode & Pipeline Register
    // ============================================================

    reg q_tile_mode_op;
    reg q_tile_en_op;
    reg q_tile_wb_op;
    reg q_core_out_op;
    reg q_error_op;

    assign o_tile_mode_op = i_backend_stall ? 1'b0 : q_tile_mode_op;
    assign o_tile_en_op   = i_backend_stall ? 1'b0 : q_tile_en_op;
    assign o_tile_wb_op   = i_backend_stall ? 1'b0 : q_tile_wb_op; // 防止 FIFO 爆掉
    assign o_core_out_op  = i_backend_stall ? 1'b0 : q_core_out_op;
    assign o_error_op     = i_backend_stall ? 1'b0 : q_error_op;


    // 1. 取出 32-bit 指令
    wire [31:0] inst = main_valid ? main_buffer : {6'b011000, 26'd0}; //B_SYNC but don't wait any
    
    // 2. Opcode 提取
    wire [5:0] w_opcode = inst[31:26];

    // 3. SubDecoder 實例化
    wire w_regfile_tile_wb_op;
    wire w_regfile_core_in_op;
    wire w_regfile_read_op;
    wire w_block_sync_op;
    wire w_tile_mode_op;
    wire w_tile_en_op;
    wire w_tile_wb_op;
    wire w_core_out_op;
    wire w_error_op;

    SubDecoder u_SubDec (
        .i_sub_op       (w_opcode),
        .i_sub_op_valid (main_valid),
        .o_regfile_tile_wb_op (w_regfile_tile_wb_op),
        .o_regfile_core_in_op (w_regfile_core_in_op),
        .o_regfile_read_op    (w_regfile_read_op),
        .o_block_sync_op      (w_block_sync_op),
        .o_tile_mode_op       (w_tile_mode_op),
        .o_tile_en_op         (w_tile_en_op),
        .o_tile_wb_op         (w_tile_wb_op),
        .o_core_out_op        (w_core_out_op),
        .o_error_op           (w_error_op)
    );

    // 4. Pipeline Register Update
    always @(posedge clk) begin
        if (!rst_n) begin
            o_opcode <= 0;
            // ... Reset all control signals ...
            o_regfile_read_op <= 0;
            o_regfile_core_in_op <= 0;
            o_regfile_tile_wb_op <= 0;
            o_block_sync_op <= 0;

            q_tile_mode_op <= 0;
            q_tile_en_op <= 0;
            q_tile_wb_op <= 0;
            q_core_out_op <= 0;
            q_error_op <= 0;

            o_rf_src_sel <= 0;
            o_addr <= 0;
            o_len <= 0;
            o_agu_mode <= 0;
            o_thread_id <= 0;

            o_core_out_sel <= 0;
            o_core_out_val <= 0;
            o_core_out_tid <= 0;

            o_tile_act_sel <= 0;
            o_tile_act_tid <= 0;
            o_tile_w_sel <= 0;
            o_tile_w_tid <= 0;
            o_tile_mode <= 0;
            o_tile_relu <= 0;
            o_tile_clr_acc <= 0;
            o_tile_clr_out <= 0;
            o_tile_scale <= 0;
            o_tile_zp <= 0;

            o_wb_addr <= 0;
            o_wb_reorder <= 0;
            o_wb_dabus <= 0;
            o_wb_mask <= 0;

            o_sync_req <= 0;
            o_agu_wait <= 0;
            o_tile_wait <= 0;
            o_status <= 0;

            // (簡略: 請確保所有 output reg 都歸零)
        end else if (!i_backend_stall) begin
            
            // Flow Control

            // Decoded Ops
            o_regfile_tile_wb_op <= w_regfile_tile_wb_op;
            o_regfile_core_in_op <= w_regfile_core_in_op;
            o_regfile_read_op    <= w_regfile_read_op;
            o_block_sync_op      <= w_block_sync_op;

            q_tile_mode_op       <= w_tile_mode_op;
            q_tile_en_op         <= w_tile_en_op;
            q_tile_wb_op         <= w_tile_wb_op;
            q_core_out_op        <= w_core_out_op;
            q_error_op           <= w_error_op;

            // Field Parsing (依照 Bit Map)
            o_opcode        <= w_opcode;

            // RFBPCtrl Fields
            o_rf_src_sel    <= inst[11:0];
            o_addr          <= inst[9:0];
            o_len           <= inst[19:10];
            o_agu_mode      <= inst[21:20];
            o_thread_id     <= inst[23:22];

            // Core Output Fields
            o_core_out_sel  <= inst[1:0];
            o_core_out_val  <= inst[2];
            o_core_out_tid  <= inst[4:3];

            // Tile Fields
            o_tile_act_sel  <= inst[0];
            o_tile_act_tid  <= inst[4:3];
            o_tile_w_sel    <= inst[5];
            o_tile_w_tid    <= inst[9:8];
            o_tile_mode     <= inst[13:10];
            o_tile_relu     <= inst[14];
            o_tile_clr_acc  <= inst[15];
            o_tile_clr_out  <= inst[16];
            o_tile_scale    <= inst[15:0];
            o_tile_zp       <= inst[23:16];

            // Tile WB Fields
            o_wb_addr       <= inst[9:0];
            o_wb_reorder    <= inst[17:10];
            o_wb_dabus      <= inst[25:18];
            o_wb_mask       <= inst[29:26];


            // Barrier Fields
            o_sync_req      <= inst[4:0];
            o_agu_wait      <= inst[6:5];
            o_tile_wait     <= inst[7];
            o_status        <= inst[13:8];
        end
    end

endmodule