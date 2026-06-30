// Register File Bank Port Control
// Version B2 - Added Explicit Stall/Backpressure Logic
module RFBPCtrl(
    clk,
    rst_n,

    // --- AGU Handshake Interface ---
    i_agu_slot_ready,    // Vector: Indicates which slots are free
    i_agu_ready,         // Global ready

    // --- Instruction Inputs ---
    i_regfile_tile_wb_op,    
    i_regfile_core_in_op,    
    i_regfile_read_op,       

    i_regfile_addr,       
    i_regfile_len,        
    i_regfile_sel,    

    i_agu_mode,    
    i_thread_id,      // Instruction IN

    // --- AGU Outputs ---
    o_agu_addr,
    o_agu_len,
    o_agu_start,

    o_agu_mode,
    o_thread_id,      // Instruction OUT (to AGU)
    o_agu_read,
    o_agu_write,

    o_rfbp_sel,
    o_wen,
    o_tile_wb_is_set,

    // --- NEW: Flow Control ---
    o_stall           // Output to Fetch/Decode: "Don't Fetch / Hold current instr"
);

    localparam ADDR_WIDTH = 10;
    localparam LEN_WIDTH = 10;
    localparam SUB_INST_NUM = 4;
    localparam SELECT_WIDTH = 3;
    localparam THREAD_ID_WIDTH = 2;
    localparam AGU_MODE_WIDTH = 2;
    
    // Match AGU Internal Slots
    localparam NUM_INTERNAL_SLOTS = 2;

    input clk;
    input rst_n;

    // --- Inputs ---
    input [NUM_INTERNAL_SLOTS-1:0] i_agu_slot_ready;
    input i_agu_ready;                      

    input i_regfile_tile_wb_op;
    input i_regfile_core_in_op;
    input i_regfile_read_op;
    input [ADDR_WIDTH-1 : 0] i_regfile_addr;
    input [LEN_WIDTH-1 : 0] i_regfile_len;
    input [SELECT_WIDTH*SUB_INST_NUM-1 : 0] i_regfile_sel;
    input [AGU_MODE_WIDTH-1 : 0] i_agu_mode;
    input [THREAD_ID_WIDTH-1 : 0]i_thread_id;

    // --- Outputs ---
    output [ADDR_WIDTH-1 : 0] o_agu_addr;
    output [LEN_WIDTH-1 : 0] o_agu_len;
    output o_agu_start;
    output [AGU_MODE_WIDTH-1 : 0] o_agu_mode;
    output [THREAD_ID_WIDTH-1 : 0] o_thread_id;
    output o_agu_read;
    output o_agu_write;
    
    output [SELECT_WIDTH*SUB_INST_NUM-1 : 0] o_rfbp_sel;
    output o_wen;
    output [SUB_INST_NUM-1 : 0] o_tile_wb_is_set;
    
    // [NEW] Output Stall
    output o_stall;

    // --- Registers ---
    reg [ADDR_WIDTH-1 : 0] data_bus_agu_addr_reg;
    reg [LEN_WIDTH-1 : 0] data_bus_agu_len_reg;
    reg data_bus_agu_start_reg;
    reg [AGU_MODE_WIDTH-1 : 0] agu_mode_reg;
    reg [THREAD_ID_WIDTH-1 : 0] thread_id_reg;
    reg agu_read_reg;
    reg agu_write_reg;

    reg [SELECT_WIDTH*SUB_INST_NUM-1 : 0] sel_reg;
    reg [SUB_INST_NUM-1 : 0] tile_wb_is_set_reg;
    reg wen;

    //================================================================
    // Logic: Target Slot Resolution & Stall Generation
    //================================================================
    
    // 1. Determine which slot the INCOMING instruction wants
    //    Using MSB mapping (Time-share Static Mapping)
    wire [0:0] w_target_slot_idx;
    assign w_target_slot_idx = i_thread_id[THREAD_ID_WIDTH-1];

    // 2. Check if THAT specific slot is ready (Combinational check)
    wire w_target_slot_is_ready;
    assign w_target_slot_is_ready = i_agu_slot_ready[w_target_slot_idx];

    // 3. Identify if current instruction NEEDS the AGU
    wire w_is_agu_op;
    assign w_is_agu_op = (i_regfile_core_in_op | i_regfile_read_op);

    // 4. [CRITICAL] Stall Logic (Backpressure)
    //    If it is an AGU op, AND (Target Slot Busy OR Global AGU Busy) -> Stall
    assign o_stall = w_is_agu_op && (!w_target_slot_is_ready);

    // 5. Internal Update Enable
    //    We only process the instruction if we are NOT stalling.
    wire agu_update = w_is_agu_op && !o_stall;

    // 6. Selection Update (Configuration instruction)
    //    Usually configs don't use AGU slots, but we respect global ready just in case.
    //    (Assumes config ops don't need to stall for specific slots, only global)
    wire sel_update = i_regfile_tile_wb_op && i_agu_ready;


    // --- Assignments ---
    assign o_agu_addr = data_bus_agu_addr_reg;
    assign o_agu_len = data_bus_agu_len_reg;
    assign o_agu_start = data_bus_agu_start_reg;
    assign o_agu_mode = agu_mode_reg;
    assign o_thread_id = thread_id_reg;
    assign o_agu_read = agu_read_reg;
    assign o_agu_write = agu_write_reg;


    assign o_rfbp_sel = sel_reg;
    assign o_wen = wen;
    assign o_tile_wb_is_set = tile_wb_is_set_reg;

    always @(posedge clk) begin
        if(!rst_n) begin
            data_bus_agu_addr_reg <= 0;
            data_bus_agu_len_reg <= 0;
            data_bus_agu_start_reg <= 0;

            agu_mode_reg <= 0;
            thread_id_reg <= 0;
            agu_read_reg <= 0;
            agu_write_reg <= 0;

            sel_reg <= 0;
            wen <= 0;
            tile_wb_is_set_reg <= 0;
        end
        else begin

            // AGU Task Launch
            // Update only happens if agu_update is TRUE (which means !stall)
            data_bus_agu_addr_reg <= (agu_update)? i_regfile_addr : data_bus_agu_addr_reg;
            data_bus_agu_len_reg  <= (agu_update)? i_regfile_len  : data_bus_agu_len_reg;
            
            // Start pulse: strict 1 cycle when update occurs
            data_bus_agu_start_reg<= (agu_update)? 1'b1 : 1'b0; 

            agu_read_reg <= i_regfile_read_op && !o_stall;
            agu_write_reg <= i_regfile_core_in_op && !o_stall;


            // Configuration Update
            sel_reg <= (sel_update)? i_regfile_sel : 
                       (agu_update)? {3'd4,3'd4,3'd4,3'd4} : // Default/Clear on Action
                       sel_reg;

            // Update Mode/ID
            // Priority: sel_update (Config) > agu_update (Action)
            if (sel_update) begin
                agu_mode_reg  <= i_agu_mode;
                thread_id_reg <= i_thread_id;
            end else if (agu_update) begin
                agu_mode_reg  <= i_agu_mode;
                thread_id_reg <= i_thread_id;
            end

            // Write Enable
            wen <= (agu_update)? (agu_update == 1'b1) : wen;

            // Tile WB logic
            tile_wb_is_set_reg[0] <= (i_regfile_sel[2:0] == 3'd0)| (i_regfile_sel[5:3] == 3'd0) |
                                     (i_regfile_sel[8:6] == 3'd0) | (i_regfile_sel[11:9] == 3'd0);
            tile_wb_is_set_reg[1] <= (i_regfile_sel[2:0] == 3'd1)| (i_regfile_sel[5:3] == 3'd1) |
                                     (i_regfile_sel[8:6] == 3'd1) | (i_regfile_sel[11:9] == 3'd1);
            tile_wb_is_set_reg[2] <= (i_regfile_sel[2:0] == 3'd2)| (i_regfile_sel[5:3] == 3'd2) |
                                     (i_regfile_sel[8:6] == 3'd2) | (i_regfile_sel[11:9] == 3'd2);
            tile_wb_is_set_reg[3] <= (i_regfile_sel[2:0] == 3'd3)| (i_regfile_sel[5:3] == 3'd3) |
                                     (i_regfile_sel[8:6] == 3'd3) | (i_regfile_sel[11:9] == 3'd3);
        end
    end

endmodule