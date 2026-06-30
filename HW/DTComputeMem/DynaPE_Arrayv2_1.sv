// limit size in 4x4 
module DynaPE_Arrayv2_1 #(
    parameter ARRAY_ID = 0,
    parameter INDEX_WIDTH = 2,
    parameter ELEMENT_WIDTH = 8,
    parameter COMPUTE_WIDTH = 16,
    parameter I_PACK_WIDTH = 32,

    parameter ARRAY_HEIGHT = 4,
    parameter ARRAY_WIDTH = 4
)(
    clk,
    rst_n,

    i_act_pe_array,
    i_act_put_data_pe_array,

    i_weight_pe_array,
    i_weight_put_data_pe_array,

    i_dense_index,
    i_shift,

    i_scale,

    i_bus_select,
    i_bus_select_valid,

    i_pe_enable,

    i_mode,
    i_clear_pe_acc, // Clear PE Accumulator
    i_clear_pe_out, // Clear PE Output

    o_data_bus,
    o_data_bus_valid
);
localparam SCALE_WIDTH = 16;
localparam SELECT_WIDTH = $clog2(ARRAY_HEIGHT);
localparam COMPUTE_MODE_WIDTH = 2;
localparam SPARSE_MODE_WIDTH = 2;
localparam PE_MODE_WIDTH = COMPUTE_MODE_WIDTH + SPARSE_MODE_WIDTH;

localparam PE_O_DATA_WIDTH = COMPUTE_WIDTH*2;
localparam PE_2_BUS_WIDTH = PE_O_DATA_WIDTH*2;
localparam DATA_SCALE_WIDTH = SCALE_WIDTH + COMPUTE_WIDTH*2;
localparam BUS_O_DATA_WIDTH = PE_O_DATA_WIDTH;

input clk;
input rst_n;

input [I_PACK_WIDTH*ARRAY_HEIGHT-1:0] i_act_pe_array;
input i_act_put_data_pe_array;

input [I_PACK_WIDTH*ARRAY_WIDTH-1:0] i_weight_pe_array;
input i_weight_put_data_pe_array;

input [INDEX_WIDTH-1:0] i_dense_index;
input i_shift;

input [SCALE_WIDTH-1:0] i_scale;

input [SELECT_WIDTH*ARRAY_WIDTH-1:0] i_bus_select;
input [ARRAY_WIDTH-1:0] i_bus_select_valid;

input i_pe_enable;

input [PE_MODE_WIDTH-1:0] i_mode;
input i_clear_pe_acc;
input i_clear_pe_out;

output [BUS_O_DATA_WIDTH*ARRAY_WIDTH-1:0] o_data_bus;
output [ARRAY_WIDTH-1:0] o_data_bus_valid;

wire [I_PACK_WIDTH-1:0] in_2_act_buf [0:ARRAY_WIDTH-1];
wire [I_PACK_WIDTH-1:0] in_2_weight_buf [0:ARRAY_WIDTH-1];

wire [I_PACK_WIDTH-1:0] act_buf_2_pe_array [0:ARRAY_WIDTH-1];
wire [I_PACK_WIDTH-1:0] weight_buf_2_pe_array [0:ARRAY_HEIGHT-1];

wire [ELEMENT_WIDTH-1:0] weight_buf_systolic_data_2_pe_array [0:ARRAY_HEIGHT-1];
wire [INDEX_WIDTH-1:0] weight_buf_systolic_index_2_pe_array [0:ARRAY_HEIGHT-1];

wire [I_PACK_WIDTH*2-1:0] pe_array_2_bus [0:ARRAY_HEIGHT-1][0:ARRAY_WIDTH-1];
wire pe_array_2_bus_valid [0:ARRAY_HEIGHT-1][0:ARRAY_WIDTH-1];

genvar i, j;
generate

    for (i = 0; i < ARRAY_WIDTH; i = i + 1) begin :gen_column_and_row_buffer
        assign in_2_act_buf[i] = i_act_pe_array[I_PACK_WIDTH*(i+1)-1:I_PACK_WIDTH*i];
        assign in_2_weight_buf[i] = i_weight_pe_array[I_PACK_WIDTH*(i+1)-1:I_PACK_WIDTH*i];

        Column_Bufferv2 #(
            .BUFFER_ID(i),
            .I_DATA_WIDTH(I_PACK_WIDTH)
        ) u_act_buffer (
            .clk(clk),

            .i_data(in_2_act_buf[i]),
            .i_put_data(i_act_put_data_pe_array),
            .o_data(act_buf_2_pe_array[i])
        );

        Row_Bufferv2 #(
            .BUFFER_ID(i),
            .ELEMENT_WIDTH(ELEMENT_WIDTH),
            .IDX_WIDTH(INDEX_WIDTH),
            .SPARSE_MODE_WIDTH(SPARSE_MODE_WIDTH),
            .I_DATA_WIDTH(I_PACK_WIDTH)
        ) u_weight_buffer (
            .clk(clk),

            .i_data(in_2_weight_buf[i]),

            .i_put_data(i_weight_put_data_pe_array),
            .i_shift(i_shift),
            .i_mode(i_mode[PE_MODE_WIDTH-1:COMPUTE_MODE_WIDTH]),

            .o_systolic_data(weight_buf_systolic_data_2_pe_array[i]),
            .o_systolic_index(weight_buf_systolic_index_2_pe_array[i]),
            .o_simd_data(weight_buf_2_pe_array[i])

        );

    end

    for (i = 0; i < ARRAY_HEIGHT; i = i + 1) begin :gen_PEs

        for (j = 0; j < ARRAY_WIDTH; j = j + 1) begin :gen_PE_instance

            wire [ELEMENT_WIDTH-1:0] act_simd;
            wire [ELEMENT_WIDTH-1:0] weight_simd;

            wire [INDEX_WIDTH-1:0] weight_buf_sparse_index;
            wire [ELEMENT_WIDTH-1:0] weight_buf_systolic_data;

            assign weight_buf_sparse_index = weight_buf_systolic_index_2_pe_array[j];
            assign weight_buf_systolic_data = weight_buf_systolic_data_2_pe_array[j];

            assign act_simd = act_buf_2_pe_array[i][ELEMENT_WIDTH*j+:ELEMENT_WIDTH];
            assign weight_simd = weight_buf_2_pe_array[j][ELEMENT_WIDTH*i+:ELEMENT_WIDTH];

            PEv5 #(
                .PE_ROW_ID(i),
                .PE_COL_ID(j),
                .PRE_LOAD_WIDTH(ELEMENT_WIDTH),
                .COMPUTE_WIDTH(COMPUTE_WIDTH),
                .PACK_WIDTH(I_PACK_WIDTH),
                .O_DATA_WIDTH(PE_O_DATA_WIDTH)
            ) u_pe (
                .clk(clk),
                .rst_n(rst_n),

                .i_clear_acc(i_clear_pe_acc),
                .i_clear_out(i_clear_pe_out),
                .i_pe_enable(i_pe_enable),
                .i_mode(i_mode),

                .i_dense_index(i_dense_index),
                .i_sparse_index(weight_buf_sparse_index),

                .i_act_simd(act_simd),
                .i_weight_simd(weight_simd),

                .i_systolic_acts(act_buf_2_pe_array[i]),
                .i_systolic_weight(weight_buf_systolic_data),

                .i_scale(i_scale),

                .o_acc(),
                .o_scale_acc_up(pe_array_2_bus[i][j][I_PACK_WIDTH*2-1:I_PACK_WIDTH]),
                .o_scale_acc_down(pe_array_2_bus[i][j][I_PACK_WIDTH-1:0]),

                .o_scale_acc_valid(pe_array_2_bus_valid[i][j])
            );
        end

    end
    // (Diagnosed Access Bus)latin square bus
    for (i = 0; i < ARRAY_WIDTH; i = i + 1) begin :gen_output_diagonal_bus

        wire [PE_2_BUS_WIDTH*ARRAY_HEIGHT-1:0] pe_out_concat;
        wire [ARRAY_HEIGHT-1:0] pe_out_valid_concat;

        if (i == 0) begin
            assign pe_out_concat = {pe_array_2_bus[3][3],pe_array_2_bus[2][2],pe_array_2_bus[1][1],pe_array_2_bus[0][0]};
            assign pe_out_valid_concat = {pe_array_2_bus_valid[3][3],pe_array_2_bus_valid[2][2],pe_array_2_bus_valid[1][1],pe_array_2_bus_valid[0][0]};

        end else if (i == 1) begin
            assign pe_out_concat = {pe_array_2_bus[3][0],pe_array_2_bus[2][3],pe_array_2_bus[1][2],pe_array_2_bus[0][1]};
            assign pe_out_valid_concat = {pe_array_2_bus_valid[3][0],pe_array_2_bus_valid[2][3],pe_array_2_bus_valid[1][2],pe_array_2_bus_valid[0][1]};

        end else if (i == 2) begin
            assign pe_out_concat = {pe_array_2_bus[3][1],pe_array_2_bus[2][0],pe_array_2_bus[1][3],pe_array_2_bus[0][2]};
            assign pe_out_valid_concat = {pe_array_2_bus_valid[3][1],pe_array_2_bus_valid[2][0],pe_array_2_bus_valid[1][3],pe_array_2_bus_valid[0][2]};

        end else begin
            assign pe_out_concat = {pe_array_2_bus[3][2],pe_array_2_bus[2][1],pe_array_2_bus[1][0],pe_array_2_bus[0][3]};
            assign pe_out_valid_concat = {pe_array_2_bus_valid[3][2],pe_array_2_bus_valid[2][1],pe_array_2_bus_valid[1][0],pe_array_2_bus_valid[0][3]};
        end

        Quantize_BUS_MUX #(
            .I_DATA_WIDTH(PE_2_BUS_WIDTH),
            .DATA_SCALE_WIDTH(DATA_SCALE_WIDTH),
            .NUM_IN_PORTS(ARRAY_HEIGHT)
        ) u_quantize_bus_mux (
            .clk(clk),
            .rst_n(rst_n),

            .i_data(pe_out_concat),
            .i_data_valid(pe_out_valid_concat),

            .i_select(i_bus_select[SELECT_WIDTH*i +: SELECT_WIDTH]),
            .i_select_valid(i_bus_select_valid[i]),

            .o_shifted_result(o_data_bus[BUS_O_DATA_WIDTH*i +: BUS_O_DATA_WIDTH]),
            .o_data_valid(o_data_bus_valid[i])
        );

    end

endgenerate

endmodule