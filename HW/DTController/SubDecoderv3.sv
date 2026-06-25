module SubDecoder(
    input [5:0]  i_sub_op,
    input        i_sub_op_valid,

    output       o_regfile_tile_wb_op,
    output       o_regfile_core_in_op,
    output       o_regfile_read_op,

    output       o_tile_mode_op,
    output       o_tile_en_op,
    output       o_tile_wb_op,
    output       o_block_sync_op,

    output       o_core_out_op,

    output       o_error_op
);

    // 參數定義
    localparam R_TWB  = 6'b000000; // Tile Write back
    localparam R_CW   = 6'b001000; // Core Write RegFile
    localparam R_R    = 6'b010000; // Read
    localparam B_S    = 6'b011000; // Block-SYNC
    localparam T_SCM  = 6'b100000; // Source Mode ReLU Clear
    localparam T_ENC  = 6'b101000; // Enable Computation scale zero_point
    localparam C_OUT  = 6'b101100; // Core Output Setting
    localparam T_WB   = 2'b11;     // DABus Reorder WB_Address (High 2 bits)

    // --------------------------------------------------------
    // 簡化邏輯：
    // 使用 assign 取代 always block。
    // 邏輯為：(i_sub_op_valid) AND (opcode 匹配)
    // --------------------------------------------------------

    assign o_regfile_tile_wb_op = i_sub_op_valid && (i_sub_op == R_TWB);
    assign o_regfile_core_in_op = i_sub_op_valid && (i_sub_op == R_CW);
    assign o_regfile_read_op    = i_sub_op_valid && (i_sub_op == R_R);
    assign o_block_sync_op      = i_sub_op_valid && (i_sub_op == B_S);
    assign o_tile_mode_op       = i_sub_op_valid && (i_sub_op == T_SCM);
    assign o_tile_en_op         = i_sub_op_valid && (i_sub_op == T_ENC);
    assign o_core_out_op        = i_sub_op_valid && (i_sub_op == C_OUT);

    // 特殊處理：T_WB 只看高兩位 (op[5:4])
    // 原始程式碼中此信號未與 valid 結合 ，建議加上 valid 以避免無效數據造成的誤動作
    assign o_tile_wb_op         = i_sub_op_valid && (i_sub_op[5:4] == T_WB);

    // --------------------------------------------------------
    // Error 判斷：
    // 如果 Valid 為 High，但沒有匹配到任何合法的 OP，則報錯。
    // --------------------------------------------------------
    wire any_valid_op = o_regfile_tile_wb_op | o_regfile_core_in_op | 
                        o_regfile_read_op    | o_block_sync_op      | 
                        o_tile_mode_op       | o_tile_en_op         | 
                        o_core_out_op        | o_tile_wb_op;

    assign o_error_op = i_sub_op_valid && !any_valid_op;

endmodule