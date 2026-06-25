module Address_Generator_Timeshare #(
    parameter BASE_ADDRESS_WIDTH = 10,
    parameter LENGTH_WIDTH = 10,
    parameter MODE_WIDTH = 2,
    parameter THREAD_ID_WIDTH = 2,
    
    // *** Define internal slot count ***
    localparam NUM_INTERNAL_SLOTS = 2
)(
    clk,
    rst_n,

    // --- Inputs ---
    i_start,
    i_base_address,
    i_length,
    i_mode,         // Forced continuous
    i_thread_id,    // External ID (0-3)
    i_read,
    i_write,        // [ADDED] Write request input

    // --- Outputs ---
    o_address,
    o_ready,        // Ready only if the TARGET slot for this ID is free
    o_busy,         // Arbiter is busy (Global)
    o_valid,
    o_last,
    o_thread_id,    // External ID (0-3)
    o_read,
    o_write,        // [ADDED] Write request output

    // --- Independent Slot Status ---
    o_slot_ready,   
    o_slot_busy     
);

//================================================================
// Port Declarations
//================================================================
input                           clk;
input                           rst_n;
input                           i_start;
input [BASE_ADDRESS_WIDTH-1:0]  i_base_address;
input [LENGTH_WIDTH-1:0]        i_length;
input [MODE_WIDTH-1:0]          i_mode;
input [THREAD_ID_WIDTH-1:0]     i_thread_id;
input                           i_read;
input                           i_write; // [ADDED]
output [BASE_ADDRESS_WIDTH-1:0] o_address;
output                          o_ready;
output                          o_busy;
output                          o_valid;
output                          o_last;
output [THREAD_ID_WIDTH-1:0]    o_thread_id;
output                          o_read;
output                          o_write; // [ADDED]
output [NUM_INTERNAL_SLOTS-1:0] o_slot_ready;
output [NUM_INTERNAL_SLOTS-1:0] o_slot_busy;

//================================================================
// Per-Thread Internal State Registers
//================================================================
reg r_ac_start [NUM_INTERNAL_SLOTS-1:0];
reg [BASE_ADDRESS_WIDTH-1:0] r_address_next [NUM_INTERNAL_SLOTS-1:0];
reg [LENGTH_WIDTH-1:0] r_down_counter [NUM_INTERNAL_SLOTS-1:0];
reg [MODE_WIDTH-1:0] r_mode_reg [NUM_INTERNAL_SLOTS-1:0];     
reg [MODE_WIDTH-1:0] r_mode_counter [NUM_INTERNAL_SLOTS-1:0];

// Rename mapping table
reg [THREAD_ID_WIDTH-1:0] r_external_id_map [NUM_INTERNAL_SLOTS-1:0];
reg r_read_reg [NUM_INTERNAL_SLOTS-1:0];
reg r_write_reg [NUM_INTERNAL_SLOTS-1:0]; // [ADDED] Write state register

//================================================================
// Combinational Wires
//================================================================
genvar gv_i;

// --- Arbitration Wires ---
wire w_wants_subsequent_beat [NUM_INTERNAL_SLOTS-1:0];
wire w_any_subsequent_beat;
// --- Slot allocation logic ---
wire [0:0] w_target_slot;           // Derived from ID MSB
wire w_target_slot_is_free;
wire w_id_is_already_active;

wire w_wants_new_task;
wire w_wants_new_task_with_slot;
wire w_wants_single_beat_insert_only;

// --- Arbiter Output Wires ---
reg w_selected_valid;
reg [0:0]                       w_selected_internal_slot;
reg [THREAD_ID_WIDTH-1:0]       w_selected_external_id;
reg [BASE_ADDRESS_WIDTH-1:0]    w_selected_address;
reg w_selected_last;
reg w_selected_read;
reg w_selected_write; // [ADDED]

//================================================================
// Combinational Logic
//================================================================

// *** CHANGED: Determine Target Slot by MSB ***
// If THREAD_ID_WIDTH is 2, MSB is bit [1].
// ID 0, 1 -> Slot 0
// ID 2, 3 -> Slot 1
assign w_target_slot = i_thread_id[THREAD_ID_WIDTH-1];
// Check if this specific target slot is free
assign w_target_slot_is_free = !r_ac_start[w_target_slot];
// Check duplicate ID (Safety check)
wire w_id_is_active_in_slot0 = r_ac_start[0] && (r_external_id_map[0] == i_thread_id);
wire w_id_is_active_in_slot1 = r_ac_start[1] && (r_external_id_map[1] == i_thread_id);
assign w_id_is_already_active = w_id_is_active_in_slot0 || w_id_is_active_in_slot1;
// *** CHANGED: Global Ready Logic ***
// Ready only if:
// 1. The ID is not already running (duplicate check)
// 2. The SPECIFIC slot mapped to this ID is free.
assign o_ready = !w_id_is_already_active && w_target_slot_is_free;

// --- Subsequent Beat Logic ---
generate
    for (gv_i = 0; gv_i < NUM_INTERNAL_SLOTS; gv_i = gv_i + 1) begin : gen_subsequent_check
        assign w_wants_subsequent_beat[gv_i] = r_ac_start[gv_i] && (r_mode_counter[gv_i] == 0);
    end
endgenerate

assign w_any_subsequent_beat = w_wants_subsequent_beat[0] || w_wants_subsequent_beat[1];
assign o_busy = w_any_subsequent_beat;

// Independent Slot Status
assign o_slot_ready[0] = ~r_ac_start[0];
assign o_slot_ready[1] = ~r_ac_start[1];
assign o_slot_busy[0]  = w_wants_subsequent_beat[0];
assign o_slot_busy[1]  = w_wants_subsequent_beat[1];
// New Task Request
assign w_wants_new_task = i_start && o_ready; 
// Note: o_ready already checks w_target_slot_is_free, so w_wants_new_task implies we have the slot.
assign w_wants_new_task_with_slot = w_wants_new_task; 

// Single beat insert logic (Optimization for length=0)
assign w_wants_single_beat_insert_only = 1'b0;


// --- Arbiter Logic ---
always_comb begin
    // Defaults
    w_selected_valid         = 1'b0;
    w_selected_internal_slot = 1'b0;
    w_selected_external_id   = '0;
    w_selected_address       = '0;
    w_selected_last          = 1'b0;
    w_selected_read          = 1'b0;
    w_selected_write         = 1'b0; // [ADDED] Default
    
    // Prio 1: Subsequent beat, Slot 0
    if (w_wants_subsequent_beat[0]) begin
        w_selected_valid         = 1'b1;
        w_selected_internal_slot = 1'b0;
        w_selected_external_id   = r_external_id_map[0];
        w_selected_address       = r_address_next[0];
        w_selected_last          = (r_down_counter[0] == 0);
        w_selected_read          = r_read_reg[0];
        w_selected_write         = r_write_reg[0]; // [ADDED]
    end
    // Prio 2: Subsequent beat, Slot 1
    else if (w_wants_subsequent_beat[1]) begin
        w_selected_valid         = 1'b1;
        w_selected_internal_slot = 1'b1;
        w_selected_external_id   = r_external_id_map[1];
        w_selected_address       = r_address_next[1];
        w_selected_last          = (r_down_counter[1] == 0);
        w_selected_read          = r_read_reg[1];
        w_selected_write         = r_write_reg[1]; // [ADDED]
    end 
    // Prio 3: New task
    else if (w_wants_new_task_with_slot) begin
        w_selected_valid         = 1'b1;
        // *** CHANGED: Use the target slot derived from ID ***
        w_selected_internal_slot = w_target_slot;
        w_selected_external_id   = i_thread_id;
        w_selected_address       = i_base_address;
        w_selected_last          = (i_length == 0);
        w_selected_read          = i_read;
        w_selected_write         = i_write; // [ADDED] Pass through input
    end
end

// --- Final Outputs ---
assign o_valid     = w_selected_valid;
assign o_address   = w_selected_address;
assign o_last      = w_selected_last;
assign o_thread_id = w_selected_external_id;
assign o_read      = w_selected_read;
assign o_write     = w_selected_write; // [ADDED]

//================================================================
// Sequential Logic
//================================================================
always_ff @(posedge clk) begin
    integer i;
    if (!rst_n) begin
        for (i = 0; i < NUM_INTERNAL_SLOTS; i = i + 1) begin
            r_ac_start[i]        <= 1'b0;
            r_address_next[i]    <= '0;
            r_down_counter[i]    <= '0;
            r_mode_reg[i]        <= '0;
            r_mode_counter[i]    <= '0;
            r_external_id_map[i] <= '0;
            r_read_reg[i]        <= 1'b0;
            r_write_reg[i]       <= 1'b0; // [ADDED] Reset
        end
    end else begin

        // --- Process new task ---
        if (w_wants_new_task_with_slot) begin
            if (i_length >= 1) begin
                // Register task into the TARGET slot
                r_ac_start[w_target_slot]        <= 1'b1;
                r_external_id_map[w_target_slot] <= i_thread_id;
                
                r_address_next[w_target_slot]    <= i_base_address + 1;
                r_down_counter[w_target_slot]    <= i_length - 1;
                r_mode_reg[w_target_slot]        <= i_mode;
                r_mode_counter[w_target_slot]    <= i_mode;
                r_read_reg[w_target_slot]        <= i_read;
                r_write_reg[w_target_slot]       <= i_write; // [ADDED] Capture input
            end
        end

        // --- Process active tasks ---
        for (i = 0; i < NUM_INTERNAL_SLOTS; i = i + 1) begin
            if (r_ac_start[i]) begin
                
                if (w_selected_valid && (w_selected_internal_slot == i)) begin
                    
                    if (w_wants_subsequent_beat[i] && (r_down_counter[i] == 0)) 
                    begin
                        // Task complete
                        r_ac_start[i] <= 1'b0;
                        r_external_id_map[i] <= '0;
                        r_read_reg[i] <= 1'b0;
                        r_write_reg[i] <= 1'b0; // [ADDED] Clear
                    end 
                    else begin
                        // Next beat
                        r_address_next[i] <= r_address_next[i] + 1;
                        r_down_counter[i] <= r_down_counter[i] - 1;
                        r_mode_counter[i] <= r_mode_reg[i]; 
                    end
                end
                else if (r_mode_counter[i] > 0) begin
                    r_mode_counter[i] <= r_mode_counter[i] - 1;
                end
            end
        end 
    end 
end 

endmodule