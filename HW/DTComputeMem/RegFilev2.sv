// Version C0
module RegFile#(
//--------------------------------------------------------------------------
parameter BRAM_INST_NUM = 8, // Number of instances
parameter SUB_RAM_ADDR_WIDTH = 10,
parameter RAM_DATA_WIDTH = 32,
parameter THREAD_ID_WIDTH = 2,
parameter TILE_INST = 4,
parameter MASK_WIDTH = 4
//----------------------------------------------------------------------
)(
    input clk,

    input [1:0] i_en_act_bus,
    input [1:0] i_en_weight_bus,

    input [1:0] i_wen_act_bus,
    input [1:0] i_wen_weight_bus,
    // write back data
    input [TILE_INST*RAM_DATA_WIDTH-1:0] i_wb_data,
    input [TILE_INST-1:0] i_wb_data_valid,
    // write back address
    input [TILE_INST*SUB_RAM_ADDR_WIDTH-1:0] i_wb_addr,
    input [TILE_INST-1:0] i_wb_addr_valid,
    input [MASK_WIDTH-1:0] i_wb_mask [TILE_INST-1:0],


    input [BRAM_INST_NUM*3-1:0] i_act_src_sel, //select Act input Port Data & address sourceMap 1-Bank-1-port(3-bit*4 => 12-bit)
    input [BRAM_INST_NUM*3-1:0] i_weight_src_sel, //select Weight input Port Data & address sourceMap 1-Bank-1-port(3-bit*4 => 12-bit)

    input [BRAM_INST_NUM*RAM_DATA_WIDTH-1:0] i_act_data_bus,
    input [BRAM_INST_NUM*RAM_DATA_WIDTH-1:0] i_weight_data_bus,

    input [SUB_RAM_ADDR_WIDTH*2-1:0] i_act_data_bus_addr,
    input [SUB_RAM_ADDR_WIDTH*2-1:0] i_weight_data_bus_addr,

    output [(RAM_DATA_WIDTH*BRAM_INST_NUM)-1:0] o_act_bus,
    output [(RAM_DATA_WIDTH*BRAM_INST_NUM)-1:0] o_weight_bus
);
    
genvar i;
generate

    for ( i = 0; i < BRAM_INST_NUM; i = i + 1) begin : gen_bram_inst

        wire en_a, en_sel_a, en_b, en_sel_b, wen_a, wen_b;

        wire [RAM_DATA_WIDTH-1:0] act;
        wire [RAM_DATA_WIDTH-1:0] weight;

        wire [SUB_RAM_ADDR_WIDTH-1:0] act_addr;
        wire [SUB_RAM_ADDR_WIDTH-1:0] act_data_bus_addr;

        wire [SUB_RAM_ADDR_WIDTH-1:0] weight_addr;
        wire [SUB_RAM_ADDR_WIDTH-1:0] weight_data_bus_addr;

        wire [MASK_WIDTH-1:0] mask;

        if (i < 4) begin
            assign mask = {i_wb_mask[3][i],i_wb_mask[2][i],i_wb_mask[1][i],i_wb_mask[0][i]};

        end else begin
            assign mask = {i_wb_mask[3][i-4],i_wb_mask[2][i-4],i_wb_mask[1][i-4],i_wb_mask[0][i-4]};

        end

        // Act data
        assign act = (i_act_src_sel[(i+1)*3-1:i*3] == 0)? i_wb_data[31:0]:
                     (i_act_src_sel[(i+1)*3-1:i*3] == 1)? i_wb_data[63:32]:
                     (i_act_src_sel[(i+1)*3-1:i*3] == 4)? i_act_data_bus[(i+1)*RAM_DATA_WIDTH-1:i*RAM_DATA_WIDTH]:32'd0;
        assign act_data_bus_addr = (i < 4)? i_act_data_bus_addr[9:0]:i_act_data_bus_addr[19:10];
        assign act_addr = (i_act_src_sel[(i+1)*3-1:i*3] == 0)? i_wb_addr[9:0]:
                          (i_act_src_sel[(i+1)*3-1:i*3] == 1)? i_wb_addr[19:10]:
                          (i_act_src_sel[(i+1)*3-1:i*3] == 4)? act_data_bus_addr:10'd0;

        // Weight data
        assign weight = (i_weight_src_sel[(i+1)*3-1:i*3] == 2)? i_wb_data[95:64]:
                        (i_weight_src_sel[(i+1)*3-1:i*3] == 3)? i_wb_data[127:96]:
                        (i_weight_src_sel[(i+1)*3-1:i*3] == 4)? i_weight_data_bus[(i+1)*RAM_DATA_WIDTH-1:i*RAM_DATA_WIDTH]:32'd0;
        assign weight_data_bus_addr = (i < 4)? i_weight_data_bus_addr[9:0]:i_weight_data_bus_addr[19:10];
        assign weight_addr = (i_weight_src_sel[(i+1)*3-1:i*3] == 2)? i_wb_addr[29:20]:
                          (i_weight_src_sel[(i+1)*3-1:i*3] == 3)? i_wb_addr[39:30]:
                          (i_weight_src_sel[(i+1)*3-1:i*3] == 4)? weight_data_bus_addr:10'd0;
        
        // Write enable A-port(Act)
        assign wen_a = (i_act_src_sel[(i+1)*3-1:i*3] == 0)? i_wb_addr_valid[0]&i_wb_data_valid[0]&mask[0]:
                       (i_act_src_sel[(i+1)*3-1:i*3] == 1)? i_wb_addr_valid[1]&i_wb_data_valid[1]&mask[1]:
                       (i_act_src_sel[(i+1)*3-1:i*3] == 4)? (i < 4 ? i_wen_act_bus[0] : i_wen_act_bus[1]):1'b0;
        assign en_sel_a = (i < 4)? i_en_act_bus[0]:i_en_act_bus[1];
        assign en_a = en_sel_a | wen_a;

        // Write enable B-port(Weight)
        assign wen_b = (i_weight_src_sel[(i+1)*3-1:i*3] == 2)? i_wb_addr_valid[2]&i_wb_data_valid[2]&mask[2]:
                       (i_weight_src_sel[(i+1)*3-1:i*3] == 3)? i_wb_addr_valid[3]&i_wb_data_valid[3]&mask[3]:
                       (i_weight_src_sel[(i+1)*3-1:i*3] == 4)? (i < 4 ? i_wen_weight_bus[0] : i_wen_weight_bus[1]):1'b0;
        assign en_sel_b = (i < 4)? i_en_weight_bus[0]:i_en_weight_bus[1];
        assign en_b = en_sel_b | wen_b;



            BRAM32DP #(
                .ADDR_WIDTH(SUB_RAM_ADDR_WIDTH),
                .DATA_WIDTH(RAM_DATA_WIDTH)
            ) u_bram_inst (
                .clk(clk),
            
                .ena(en_a),
                .enb(en_b),

                .wen_a(wen_a),
                .wen_b(wen_b),

                .addr_a(act_addr),
                .addr_b(weight_addr),

                .din_a(act),
                .din_b(weight),

                .dout_a(o_act_bus[(i+1)*RAM_DATA_WIDTH-1:i*RAM_DATA_WIDTH]),
                .dout_b(o_weight_bus[(i+1)*RAM_DATA_WIDTH-1:i*RAM_DATA_WIDTH])
            );

    end

endgenerate

endmodule

module BRAM32DP#(

parameter ADDR_WIDTH = 10,
parameter DATA_WIDTH = 32
)( 
    input clk,
    input ena,
    input enb,

    input wen_a,
    input wen_b,

    input [ADDR_WIDTH-1:0] addr_a,
    input [ADDR_WIDTH-1:0] addr_b,

    input [DATA_WIDTH-1:0] din_a,
    input [DATA_WIDTH-1:0] din_b,

    output reg [DATA_WIDTH-1:0] dout_a,
    output reg [DATA_WIDTH-1:0] dout_b
);
    
(* ram_style = "block" ,cascade_height = 1 *)
reg [DATA_WIDTH-1:0] ram_block [(2**ADDR_WIDTH)-1:0];

always @(posedge clk) begin
    if (ena) begin
        if (wen_a) begin
            ram_block[addr_a] <= din_a;
        end
        dout_a <= ram_block[addr_a];
    end
end

always @(posedge clk) begin
    if (enb) begin
        if (wen_b) begin
            ram_block[addr_b] <= din_b;
        end 
        dout_b <= ram_block[addr_b];
    end
end


endmodule