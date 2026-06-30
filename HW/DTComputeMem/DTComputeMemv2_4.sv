// Version B4
module DTComputeMemv2_4 #(
    parameter CORE_ID = 0,
    parameter TILE_INST = 4,
    parameter BRAM_INST = 8,
    parameter SCALE_WIDTH = 16,
    parameter ZERO_POINT_WIDTH = 8,
    parameter RELU_WIDTH = 8,
    parameter SUB_RAM_ADDR_WIDTH = 10
)(
    clk,

    rst_n,

    i_core_data,
    i_core_data_thread_id,

    o_core_data,
    o_core_data_thread_id,
    
    o_core_data_last,
    // Tile Act/Weight Control Signal
    i_tile_act_select,
    i_tile_weight_select,

    // RegFile Control Signal
    i_rfbp_sel,

    // Address Generator Uint Signal
    i_agu_start,
    i_agu_address,
    i_agu_length,
    i_agu_mode,
    i_agu_thread_id,
    i_agu_read,
    i_agu_write,

    o_agu_ready,
    o_agu_busy,

    o_agu_slot_ready,
    o_agu_slot_busy,

    // Tile Write Back Address Signal
    i_wb_addr,
    i_wb_valid,
    i_wb_mask,

    // Tile Control signal
    i_tile_bus_mux,
    i_tile_bus_mux_valid,

    i_tile_reorder,
    i_tile_reorder_valid,

    i_tile_enable,
    i_tile_mode,

    i_tile_act_thread_id,
    i_tile_weight_thread_id,

    i_tile_clear_pe_acc,
    i_tile_clear_pe_out,

    o_tile_busy,
    // Qunatizer Control Singal
    i_inv_scale_fixed_point,
    i_zero_point,

    i_relu_data_valid,

    // AGU Write for Read Data from Top Data FIFO to RegFile
    o_read_data,

    // Core Output Data Select Signal
    i_core_output_select // output data valid handle by core top module check sel_valid and thread_id 
);
localparam PE_MODE_WIDTH = 4;
localparam NUM_PORT = 4;
localparam CORE_PORT_DATA_WIDTH = 128;
localparam CORE_OUTPUT_SEL_WIDTH = 2;

localparam REGFILE_DATA_BUS_WIDTH = 256;

localparam TILE_ACT_DATA_WIDTH = 128;
localparam TILE_WEIGHT_DATA_WIDTH = 128;

localparam TILE_ACT_SELECT_WIDTH = 1;
localparam TILE_WEIGHT_SELECT_WIDTH = 1;

localparam TILE_O_DATA_WIDTH = 32;

localparam INV_SCALE_WIDTH = 16;

localparam BM_QO_SELECT_WIDTH = 8;

localparam REGFILE_PORT_INST = 4;

localparam AGU_MODE_WIDTH = 2;
localparam THREAD_ID_WIDTH = 2;

localparam ARRAY_HEIGHT = 4;
localparam ARRAY_WIDTH = 4;

localparam NUM_INTERNAL_SLOTS = 2;


input clk;

input rst_n;
input  [CORE_PORT_DATA_WIDTH-1:0] i_core_data [NUM_PORT-1:0];
input  [THREAD_ID_WIDTH-1:0] i_core_data_thread_id [NUM_PORT-1:0];

output [CORE_PORT_DATA_WIDTH-1:0] o_core_data [NUM_PORT-1:0];
output [THREAD_ID_WIDTH-1:0] o_core_data_thread_id [NUM_PORT-1:0];

output [NUM_PORT-1:0] o_core_data_last;

// Tile Act/Weight Control Signal
input [TILE_ACT_SELECT_WIDTH-1:0] i_tile_act_select [TILE_INST-1:0];
input [TILE_WEIGHT_SELECT_WIDTH-1:0] i_tile_weight_select [TILE_INST-1:0];

input [((BRAM_INST/2)*3)-1:0] i_rfbp_sel [REGFILE_PORT_INST-1:0];
// Address Generator Uint Signal
input [TILE_INST-1:0] i_agu_start;
input [SUB_RAM_ADDR_WIDTH-1:0] i_agu_address [TILE_INST-1:0];
input [SUB_RAM_ADDR_WIDTH-1:0] i_agu_length [TILE_INST-1:0];
input [AGU_MODE_WIDTH-1:0] i_agu_mode [TILE_INST-1:0];
input [THREAD_ID_WIDTH-1:0] i_agu_thread_id [TILE_INST-1:0];
input [TILE_INST-1:0] i_agu_read;
input [TILE_INST-1:0] i_agu_write;

output[TILE_INST-1:0] o_agu_ready;
output[TILE_INST-1:0] o_agu_busy;

output [NUM_INTERNAL_SLOTS-1:0] o_agu_slot_ready [TILE_INST-1:0];
output [NUM_INTERNAL_SLOTS-1:0] o_agu_slot_busy [TILE_INST-1:0];

// Tile Write Back Address Generator Uint Signal
input [SUB_RAM_ADDR_WIDTH-1:0] i_wb_addr [TILE_INST-1:0];
input [TILE_INST-1:0] i_wb_valid;
input [3:0] i_wb_mask [TILE_INST-1:0];

// Tile Control signal
input [BM_QO_SELECT_WIDTH-1:0] i_tile_bus_mux [TILE_INST-1:0];
input [TILE_INST-1:0] i_tile_bus_mux_valid;

input [BM_QO_SELECT_WIDTH-1:0] i_tile_reorder [TILE_INST-1:0];
input [TILE_INST-1:0] i_tile_reorder_valid;

input [TILE_INST-1:0] i_tile_enable;
input [PE_MODE_WIDTH-1:0] i_tile_mode [TILE_INST-1:0];

input [TILE_INST-1:0] i_tile_clear_pe_acc;
input [TILE_INST-1:0] i_tile_clear_pe_out;

input [THREAD_ID_WIDTH-1:0] i_tile_act_thread_id [TILE_INST-1:0];
input [THREAD_ID_WIDTH-1:0] i_tile_weight_thread_id [TILE_INST-1:0];

output [TILE_INST-1:0] o_tile_busy;

input [INV_SCALE_WIDTH-1:0] i_inv_scale_fixed_point [TILE_INST-1:0];
input [ZERO_POINT_WIDTH-1:0] i_zero_point [TILE_INST-1:0];

input [TILE_INST-1:0] i_relu_data_valid;


// AGU Write for Read Data from Top Data FIFO to RegFile
output [NUM_PORT-1:0] o_read_data;

// Core Output Data Select Signal
input [CORE_OUTPUT_SEL_WIDTH-1:0] i_core_output_select [NUM_PORT-1:0];

//===================== Data bus connections =====================

wire [255:0] i_core_act = {i_core_data[1], i_core_data[0]}; // Input activation bus
wire [255:0] i_core_weight = {i_core_data[3], i_core_data[2]}; // Input weight bus

//===================== RegFile connections =====================

wire [SUB_RAM_ADDR_WIDTH-1:0] agu_addr [REGFILE_PORT_INST-1:0]; // Weight_H, Weight_L, Act_H, Act_L
wire [REGFILE_PORT_INST-1:0] agu_valid; // Weight_H, Weight_L, Act_H, Act_L

wire [THREAD_ID_WIDTH-1:0] agu_thread_id [REGFILE_PORT_INST-1:0];
wire [REGFILE_PORT_INST-1:0] agu_last;

reg [THREAD_ID_WIDTH-1:0] agu_thread_id_delay [REGFILE_PORT_INST-1:0];
reg [REGFILE_PORT_INST-1:0] agu_last_delay;

wire [REGFILE_DATA_BUS_WIDTH-1:0] regfile_o_act;
wire [REGFILE_DATA_BUS_WIDTH-1:0] regfile_o_weight;

genvar i;
generate
    for(i = 0; i < REGFILE_PORT_INST; i = i + 1)begin
        always @(posedge clk) begin
            
            if(!rst_n)begin
                agu_thread_id_delay[i] <= 0;
                agu_last_delay[i] <= 0;
            end
            else begin
                agu_thread_id_delay[i] <= agu_thread_id[i];
                agu_last_delay[i] <= agu_last[i];
            end
            
        end
    end
    
endgenerate


//===================== Tensor Tile connections =====================

wire [TILE_ACT_DATA_WIDTH-1:0] tile_act_bus [TILE_INST-1:0];
wire [TILE_WEIGHT_DATA_WIDTH-1:0] tile_weight_bus [TILE_INST-1:0];

wire [TILE_INST-1:0] tile_act_valid;
wire [TILE_INST-1:0] tile_weight_valid;

wire [TILE_O_DATA_WIDTH-1:0] tile_o_data [TILE_INST-1:0]; // Output data bus for each tile
wire [ARRAY_WIDTH-1:0] tile_o_data_valid [TILE_INST-1:0]; //

wire [TILE_O_DATA_WIDTH*TILE_INST-1:0] tile_o_data_concat = {tile_o_data[3], tile_o_data[2], tile_o_data[1], tile_o_data[0]};
wire [TILE_INST-1:0] tile_o_data_valid_concat ;


generate
    for(i = 0; i < TILE_INST; i = i + 1)begin
        assign tile_o_data_valid_concat[i] = |tile_o_data_valid[i];
    end
endgenerate



//===================== Tile Act/Weight MUX =====================
wire [THREAD_ID_WIDTH-1:0] act_data_thread_id [TILE_INST-1:0];
wire [THREAD_ID_WIDTH-1:0] weight_data_thread_id [TILE_INST-1:0];

wire [REGFILE_PORT_INST-1:0] agu_read_valid;
reg [REGFILE_PORT_INST-1:0] regfile_data_valid;

always@(posedge clk) begin
    if (!rst_n) begin
        regfile_data_valid <= 0;
    end else begin
        regfile_data_valid <= agu_read_valid;
    end

end

generate
    for(i = 0; i < TILE_INST; i = i + 1)begin

        // Act Select
        assign tile_act_bus[i] = (i_tile_act_select[i] == 0) ? regfile_o_act[127:0]: regfile_o_act[255:128];
        assign tile_act_valid[i] = (i_tile_act_select[i] == 0) ? regfile_data_valid[0]: regfile_data_valid[1];

        // Weight Select
        assign tile_weight_bus[i] = (i_tile_weight_select[i] == 0) ? regfile_o_weight[127:0]: regfile_o_weight[255:128];
        assign tile_weight_valid[i] = (i_tile_weight_select[i] == 0) ? regfile_data_valid[2]: regfile_data_valid[3];

        assign act_data_thread_id[i] = (i_tile_act_select[i] == 0) ? agu_thread_id_delay[0]: agu_thread_id_delay[1];

        assign weight_data_thread_id[i] = (i_tile_weight_select[i] == 0) ? agu_thread_id_delay[2]: agu_thread_id_delay[3];

    end
endgenerate


//===================== Core Output Data Bus MUX =====================

generate
    for(i = 0; i < NUM_PORT; i = i + 1)begin
        assign o_core_data[i] = (i_core_output_select[i] == 0)? regfile_o_act[127:0]:
                                (i_core_output_select[i] == 1)? regfile_o_act[255:128]:
                                (i_core_output_select[i] == 2)? regfile_o_weight[127:0]:
                                (i_core_output_select[i] == 3)? regfile_o_weight[255:128]:
                                0;

        assign o_core_data_thread_id[i] = (i_core_output_select[i] == 0)? agu_thread_id_delay[0]:
                                          (i_core_output_select[i] == 1)? agu_thread_id_delay[1]:
                                          (i_core_output_select[i] == 2)? agu_thread_id_delay[2]:
                                          (i_core_output_select[i] == 3)? agu_thread_id_delay[3]:
                                          0;

        assign o_core_data_last[i] = (i_core_output_select[i] == 0)? agu_last_delay[0]:
                                     (i_core_output_select[i] == 1)? agu_last_delay[1]:
                                     (i_core_output_select[i] == 2)? agu_last_delay[2]:
                                     (i_core_output_select[i] == 3)? agu_last_delay[3]:
                                     0;

    end
endgenerate

//===================== RegFile =====================
// rfbp : Register File Bank Port
wire [3:0] agu_write;

assign o_read_data = agu_write;

RegFile #(
    .BRAM_INST_NUM(BRAM_INST),
    .SUB_RAM_ADDR_WIDTH(10),
    .RAM_DATA_WIDTH(32),
    .TILE_INST(TILE_INST)
) u_RegFile (

    .clk(clk),
    .i_en_act_bus(agu_valid[1:0]),
    .i_en_weight_bus(agu_valid[3:2]),

    .i_wen_act_bus(agu_write[1:0]),
    .i_wen_weight_bus(agu_write[3:2]),

    .i_wb_data(tile_o_data_concat),
    .i_wb_data_valid(tile_o_data_valid_concat),

    .i_wb_addr({i_wb_addr[3], i_wb_addr[2], i_wb_addr[1],i_wb_addr[0]}),
    .i_wb_addr_valid(i_wb_valid),
    .i_wb_mask(i_wb_mask),

    .i_act_src_sel({i_rfbp_sel[1],i_rfbp_sel[0]}),
    .i_weight_src_sel({i_rfbp_sel[3],i_rfbp_sel[2]}),

    .i_act_data_bus(i_core_act),
    .i_weight_data_bus(i_core_weight),

    .i_act_data_bus_addr({agu_addr[1],agu_addr[0]}),
    .i_weight_data_bus_addr({agu_addr[3],agu_addr[2]}),

    .o_act_bus(regfile_o_act),
    .o_weight_bus(regfile_o_weight)

);


//===================== Address Generator Uint =====================
// 0:Low-Bank-Act 1:High-Bank-Act 2:Low-Bank-Weight 3:High-Bank-Weight
generate

    for(i = 0; i < TILE_INST; i = i + 1) begin : gen_data_bus_addr_counter

        Address_Generator_Timeshare #(
            .BASE_ADDRESS_WIDTH(10),
            .LENGTH_WIDTH(10),
            .MODE_WIDTH(2),
            .THREAD_ID_WIDTH(2)
        ) u_Addr_Generator_Timeshare (
            .clk(clk),
            .rst_n(rst_n),

            .i_start(i_agu_start[i]),
            .i_base_address(i_agu_address[i]),
            .i_length(i_agu_length[i]),
            .i_mode(i_agu_mode[i]),     //DTController
            .i_thread_id(i_agu_thread_id[i]),//DTController
            .i_read(i_agu_read[i]),
            .i_write(i_agu_write[i]),

            // --- Outputs ---

            .o_address(agu_addr[i]),
            .o_ready(o_agu_ready[i]),
            .o_busy(o_agu_busy[i]),
            .o_valid(agu_valid[i]),
            .o_last(agu_last[i]), //Add one-level to match Data to Core output
            .o_thread_id(agu_thread_id[i]), //Add one-level to match Data
            .o_read(agu_read_valid[i]),
            .o_write(agu_write[i]),


            .o_slot_ready(o_agu_slot_ready[i]),
            .o_slot_busy(o_agu_slot_busy[i])
        );

    end
endgenerate

//===================== Tensor Tile =====================

generate
    for (i = 0; i < TILE_INST; i = i + 1) begin : gen_tensor_tile_inst

        Tensor_Tilev2_1 #(
            .TILE_ID(i),
            .I_DATA_WIDTH(32),
            .O_DATA_WIDTH(8),
            .COMPUTE_WIDTH(16),
            .ARRAY_HEIGHT(ARRAY_HEIGHT),
            .ARRAY_WIDTH(ARRAY_HEIGHT)
        ) u_Tensor_Tilev2_1 (

            .clk(clk),

            .rst_n(rst_n),

            .i_act_tile(tile_act_bus[i]),
            .i_act_tile_valid(tile_act_valid[i]),
            .i_data_act_thread_id(act_data_thread_id[i]),      //Set Select Data thread-id follow data select

            .i_weight_tile(tile_weight_bus[i]),
            .i_weight_tile_valid(tile_weight_valid[i]),
            .i_data_weight_thread_id(weight_data_thread_id[i]),//Set Select Data thread-id

            .i_scale(i_inv_scale_fixed_point[i]),
            .i_zero_point(i_zero_point[i]),

            .i_relu_valid( {ARRAY_WIDTH{i_relu_data_valid[i]}} ),

            .i_bus_select(i_tile_bus_mux[i]),
            .i_bus_select_valid({i_tile_bus_mux_valid[i],i_tile_bus_mux_valid[i],i_tile_bus_mux_valid[i],i_tile_bus_mux_valid[i]}),

            .i_reorder_select(i_tile_reorder[i]),
            .i_reorder_select_valid({i_tile_reorder_valid[i],i_tile_reorder_valid[i],i_tile_reorder_valid[i],i_tile_reorder_valid[i]}),

            .i_tile_enable(i_tile_enable[i]),

            .i_tile_act_thread_id(i_tile_act_thread_id[i]),
            .i_tile_weight_thread_id(i_tile_weight_thread_id[i]), //DTController

            .i_mode(i_tile_mode[i]),
            .i_clear_pe_acc(i_tile_clear_pe_acc[i]),
            .i_clear_pe_out(i_tile_clear_pe_out[i]),

            .o_tile(tile_o_data[i]),
            .o_tile_busy(o_tile_busy[i]),
            .o_tile_valid(tile_o_data_valid[i])

        );

    end

endgenerate


endmodule