// Version B0
module TileState(

    clk,
    rst_n,

    i_tile_en_op,      //Sub Decoder out
    i_tile_mode_op,    //Sub Decoder out

    i_tile_clear_acc,  //instructon out
    i_tile_clear_out,  //instructon out
    i_tile_relu,       //instructon out
    i_tile_mode,       //instructon out

    i_tile_act_select,   //instructon out
    i_tile_weight_select,//instructon out

    i_tile_act_thread_id,
    i_tile_weight_thread_id,

    i_tile_scale,      //instructon out
    i_tile_zero_point, //instructon out

    o_tile_enable,
    o_tile_mode,
    o_tile_relu,
    o_tile_clear_acc,
    o_tile_clear_out,

    o_tile_act_thread_id,
    o_tile_weight_thread_id,

    o_tile_act_select,
    o_tile_weight_select,
    
    o_tile_scale,
    o_tile_zero_point

);

    localparam TILE_MODE_WIDTH = 4;
    localparam SELECT_WIDTH = 1;
    localparam THREAD_ID_WIDTH = 2;
    localparam SCALE_WIDTH = 16;
    localparam ZERO_POINT_WIDTH = 8;
    
    input clk;
    input rst_n;

    input i_tile_en_op;
    input i_tile_mode_op;

    input i_tile_clear_acc;
    input i_tile_clear_out;
    input i_tile_relu;
    input [TILE_MODE_WIDTH-1:0] i_tile_mode;

    input [SELECT_WIDTH-1:0] i_tile_act_select;
    input [SELECT_WIDTH-1:0] i_tile_weight_select;


    input [THREAD_ID_WIDTH-1:0] i_tile_act_thread_id;
    input [THREAD_ID_WIDTH-1:0] i_tile_weight_thread_id;

    input [SCALE_WIDTH-1:0] i_tile_scale;
    input [ZERO_POINT_WIDTH-1:0] i_tile_zero_point;

    output o_tile_enable;
    output [TILE_MODE_WIDTH-1:0] o_tile_mode;
    output o_tile_relu;
    output o_tile_clear_acc;
    output o_tile_clear_out;

    output [THREAD_ID_WIDTH-1:0] o_tile_act_thread_id;
    output [THREAD_ID_WIDTH-1:0] o_tile_weight_thread_id;

    output [SELECT_WIDTH-1:0] o_tile_act_select;
    output [SELECT_WIDTH-1:0] o_tile_weight_select;

    output [SCALE_WIDTH-1:0] o_tile_scale;
    output [ZERO_POINT_WIDTH-1:0] o_tile_zero_point;

    reg tile_enable_reg;
    reg [TILE_MODE_WIDTH-1:0] tile_mode_reg;
    reg tile_relu_reg;
    reg tile_clear_acc_reg;
    reg tile_clear_out_reg;

    reg [SELECT_WIDTH-1:0] tile_act_select_reg;
    reg [SELECT_WIDTH-1:0] tile_weight_select_reg;

    reg [THREAD_ID_WIDTH-1:0] tile_act_thread_id_reg;
    reg [THREAD_ID_WIDTH-1:0] tile_weight_thread_id_reg;

    reg [SCALE_WIDTH-1:0] tile_scale_reg;
    reg [ZERO_POINT_WIDTH-1:0] tile_zero_point_reg;

    assign o_tile_enable = tile_enable_reg;
    assign o_tile_mode = tile_mode_reg;
    assign o_tile_relu = tile_relu_reg;
    assign o_tile_clear_acc = tile_clear_acc_reg;
    assign o_tile_clear_out = tile_clear_out_reg;

    assign o_tile_act_select = tile_act_select_reg;
    assign o_tile_weight_select = tile_weight_select_reg;

    assign o_tile_act_thread_id = tile_act_thread_id_reg;
    assign o_tile_weight_thread_id = tile_weight_thread_id_reg;

    assign o_tile_scale = tile_scale_reg;
    assign o_tile_zero_point = tile_zero_point_reg;


    always @(posedge clk) begin
        if(!rst_n) begin
            tile_enable_reg <= 0;
            tile_mode_reg <= 0;
            tile_relu_reg <= 0;
            tile_clear_acc_reg <= 0;
            tile_clear_out_reg <= 0;

            tile_act_select_reg <= 0;
            tile_weight_select_reg <= 0;

            tile_act_thread_id_reg <= 0;
            tile_weight_thread_id_reg <= 0;

            tile_scale_reg <= 0;
            tile_zero_point_reg <= 0;
        end
        else begin
            tile_enable_reg <= (i_tile_en_op)? i_tile_en_op : tile_enable_reg;
            tile_mode_reg <= (i_tile_mode_op)? i_tile_mode : tile_mode_reg;
            tile_relu_reg <= (i_tile_mode_op)? i_tile_relu : tile_relu_reg;
            tile_clear_acc_reg <= (i_tile_mode_op)? i_tile_clear_acc : 1'b0;
            tile_clear_out_reg <= (i_tile_mode_op)? i_tile_clear_out : 1'b0;

            tile_act_select_reg <= (i_tile_mode_op)? i_tile_act_select : tile_act_select_reg;
            tile_weight_select_reg <= (i_tile_mode_op)? i_tile_weight_select : tile_weight_select_reg;

            tile_act_thread_id_reg <= (i_tile_mode_op)? i_tile_act_thread_id : tile_act_thread_id_reg;
            tile_weight_thread_id_reg <= (i_tile_mode_op)? i_tile_weight_thread_id : tile_weight_thread_id_reg;

            tile_scale_reg <= (i_tile_en_op)? i_tile_scale : tile_scale_reg;
            tile_zero_point_reg <= (i_tile_en_op)? i_tile_zero_point : tile_zero_point_reg;
        end
    end

endmodule