`timescale 1 ns / 1 ps
//AXI4 Master with small FWFT FIFO for Write Channel (TX)
//Small FIFO connected to write channel to bigger buffer(BRAM FIFO)


module M_AXI_DATA_F_FSM #
(
    parameter integer C_M_AXI_MAX_BURST_LEN = 256,
    parameter integer C_M_AXI_ID_WIDTH      = 1,
    parameter integer C_M_AXI_ADDR_WIDTH    = 64,
    parameter integer C_M_AXI_DATA_WIDTH    = 128
)
(
    // -----------------------------------------------------------------
    // User Interface
    // -----------------------------------------------------------------
    input  wire        i_m_w_start,      
    input  wire        i_m_r_start,      

    input  wire [31:0] i_m_w_addr_lo,    
    input  wire [31:0] i_m_w_addr_hi,    
    input  wire [31:0] i_m_w_len,        // only low 8 bit used
    input  wire [31:0] i_m_r_addr_lo,    
    input  wire [31:0] i_m_r_addr_hi,   
    input  wire [31:0] i_m_r_len,        // only low 8 bit used

    output reg         o_m_txn_done,     
    output reg         o_m_rxn_done,     
    output reg         o_m_error,        
    output reg  [1:0]  o_m_last_bresp,   
    output reg  [1:0]  o_m_last_rresp,   

    // TX FIFO Interface (Write to DDR)
    input wire  [C_M_AXI_DATA_WIDTH-1:0] i_tx_data,
    input wire                           i_tx_data_valid, // FWFT: Acts as !EMPTY
    output wire                          o_tx_fifo_ren,   // Pop next data
    
    // RX FIFO Interface (Read from DDR)
    output wire [C_M_AXI_DATA_WIDTH-1:0] o_rx_data,
    output wire                          o_rx_data_valid,
    output wire                          o_rx_fifo_wen,   
    input  wire                          i_rx_fifo_full,  // Backpressure

    // -----------------------------------------------------------------
    // AXI4 Master Interface
    // -----------------------------------------------------------------
    input wire  M_AXI_ACLK,
    input wire  M_AXI_ARESETN,

    // Write Address
    output wire [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI_AWID,
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0]  M_AXI_AWADDR,
    output wire [7 : 0]                     M_AXI_AWLEN,
    output wire [2 : 0]                     M_AXI_AWSIZE,
    output wire [1 : 0]                     M_AXI_AWBURST,
    output wire                             M_AXI_AWLOCK,
    output wire [3 : 0]                     M_AXI_AWCACHE,
    output wire [2 : 0]                     M_AXI_AWPROT,
    output wire [3 : 0]                     M_AXI_AWQOS,
    output wire                             M_AXI_AWVALID,
    input  wire                             M_AXI_AWREADY,

    // Write Data
    output wire [C_M_AXI_DATA_WIDTH-1 : 0]    M_AXI_WDATA,
    output wire [C_M_AXI_DATA_WIDTH/8-1 : 0]  M_AXI_WSTRB,
    output wire                               M_AXI_WLAST,
    output wire                               M_AXI_WVALID,
    input  wire                               M_AXI_WREADY,

    // Write Response
    input  wire [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI_BID,
    input  wire [1 : 0]                     M_AXI_BRESP,
    input  wire                             M_AXI_BVALID,
    output wire                             M_AXI_BREADY,

    // Read Address
    output wire [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI_ARID,
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0]  M_AXI_ARADDR,
    output wire [7 : 0]                     M_AXI_ARLEN,
    output wire [2 : 0]                     M_AXI_ARSIZE,
    output wire [1 : 0]                     M_AXI_ARBURST,
    output wire                             M_AXI_ARLOCK,
    output wire [3 : 0]                     M_AXI_ARCACHE,
    output wire [2 : 0]                     M_AXI_ARPROT,
    output wire [3 : 0]                     M_AXI_ARQOS,
    output wire                             M_AXI_ARVALID,
    input  wire                             M_AXI_ARREADY,

    // Read Data & Response
    input  wire [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI_RID,
    input  wire [C_M_AXI_DATA_WIDTH-1 : 0]  M_AXI_RDATA,
    input  wire [1 : 0]                     M_AXI_RRESP,
    input  wire                             M_AXI_RLAST,
    input  wire                             M_AXI_RVALID,
    output wire                             M_AXI_RREADY
);

    function integer clogb2 (input integer bit_depth);
        begin
            for(clogb2=0; bit_depth>0; clogb2=clogb2+1)
                bit_depth = bit_depth >> 1;
        end
    endfunction

    // -----------------------------------------------------------------
    // Internal Signals & Registers
    // -----------------------------------------------------------------

    wire [C_M_AXI_DATA_WIDTH-1:0] fwft_dout;
    wire                          fwft_dout_valid;
    wire                          fwft_pop_en;

    reg [C_M_AXI_ADDR_WIDTH-1:0] w_base_addr;
    reg [8:0]                    w_burst_len;
    reg [8:0]                    write_index;

    reg [C_M_AXI_ADDR_WIDTH-1:0] r_base_addr;
    reg [8:0]                    r_burst_len;
    reg [8:0]                    read_index;

    // FSM States
    typedef enum logic [2:0] {
        W_IDLE,
        W_AW_START,
        W_WRITE_DATA,
        W_BRESP,
        W_DONE
    } w_state_t;

    typedef enum logic [2:0] {
        R_IDLE,
        R_AR_START,
        R_READ_DATA,
        R_DONE
    } r_state_t;

    w_state_t w_state, w_next_state;
    r_state_t r_state, r_next_state;

    wire w_handshake = M_AXI_WVALID & M_AXI_WREADY;
    wire r_handshake = M_AXI_RVALID & M_AXI_RREADY;

    // -----------------------------------------------------------------
    // WRITE CHANNEL FSM
    // -----------------------------------------------------------------
    
    // State Transition
    always_ff @(posedge M_AXI_ACLK) begin
        if (!M_AXI_ARESETN) 
            w_state <= W_IDLE;
        else 
            w_state <= w_next_state;
    end

    // Next State Logic
    always_comb begin
        w_next_state = w_state;
        case (w_state)
            W_IDLE: begin
                if (i_m_w_start)
                    w_next_state = W_AW_START;
            end

            W_AW_START: begin
                // Wait for Address Accept
                if (M_AXI_AWREADY)
                    w_next_state = W_WRITE_DATA;
            end

            W_WRITE_DATA: begin
                // Check for Last beat handshake
                if (w_handshake && M_AXI_WLAST)
                    w_next_state = W_BRESP;
            end

            W_BRESP: begin
                // Wait for Write Response
                if (M_AXI_BVALID)
                    w_next_state = W_DONE;
            end

            W_DONE: begin
                // One cycle pulse for done
                w_next_state = W_IDLE;
            end
        endcase
    end

    // Write Logic & Outputs
    // Capture Address on Start
    always_ff @(posedge M_AXI_ACLK) begin
        if (w_state == W_IDLE && i_m_w_start) begin
            w_base_addr <= {i_m_w_addr_hi, i_m_w_addr_lo};
            w_burst_len <= i_m_w_len[7:0]; // 0-255
        end
    end

    // Write Index Counter
    always_ff @(posedge M_AXI_ACLK) begin
        if (w_state == W_IDLE || w_state == W_AW_START) begin
            write_index <= 0;
        end else if (w_state == W_WRITE_DATA && w_handshake) begin
            write_index <= write_index + 1;
        end
    end

    // AXI Write Outputs
    assign M_AXI_AWID    = 'b0;
    assign M_AXI_AWADDR  = w_base_addr;
    assign M_AXI_AWLEN   = w_burst_len;
    assign M_AXI_AWSIZE  = clogb2((C_M_AXI_DATA_WIDTH/8)-1);
    assign M_AXI_AWBURST = 2'b01; // INCR
    assign M_AXI_AWLOCK  = 1'b0;
    assign M_AXI_AWCACHE = 4'b0010;
    assign M_AXI_AWPROT  = 3'h0;
    assign M_AXI_AWQOS   = 4'h0;

    // VALID Signals controlled by State
    assign M_AXI_AWVALID = (w_state == W_AW_START);
    
    // Data Valid: Only when in Data State AND FIFO has data
    assign M_AXI_WVALID  = (w_state == W_WRITE_DATA) && fwft_dout_valid;
    
    // WLAST: Combinational logic (Current Count == Target Length)
    assign M_AXI_WLAST   = (write_index == w_burst_len) && M_AXI_WVALID;

    assign M_AXI_WDATA   = fwft_dout;
    assign M_AXI_WSTRB   = {(C_M_AXI_DATA_WIDTH/8){1'b1}};
    assign M_AXI_BREADY  = (w_state == W_BRESP);

    // FIFO Read Enable: Pop when handshaking
    assign fwft_pop_en = w_handshake;

    // User Status - Write
    always_ff @(posedge M_AXI_ACLK) begin
        if (!M_AXI_ARESETN) begin
            o_m_txn_done <= 0;
            o_m_last_bresp <= 0;
        end else begin
            if (w_state == W_DONE) begin
                o_m_txn_done <= 1;
                o_m_last_bresp <= M_AXI_BRESP;
            end else if (i_m_w_start) begin // Clear the “done” signal only when the next transmission begins
                o_m_txn_done <= 0;
            end
        end
    end

    // -----------------------------------------------------------------
    // READ CHANNEL FSM
    // -----------------------------------------------------------------
    
    // State Transition
    always_ff @(posedge M_AXI_ACLK) begin
        if (!M_AXI_ARESETN) 
            r_state <= R_IDLE;
        else 
            r_state <= r_next_state;
    end

    // Next State Logic
    always_comb begin
        r_next_state = r_state;
        case (r_state)
            R_IDLE: begin
                if (i_m_r_start)
                    r_next_state = R_AR_START;
            end

            R_AR_START: begin
                // Wait for Address Accept
                if (M_AXI_ARREADY)
                    r_next_state = R_READ_DATA;
            end

            R_READ_DATA: begin
                // Finish when Last detected
                if (r_handshake && M_AXI_RLAST)
                    r_next_state = R_DONE;
                // Safety: Also check counter in case RLAST is missing (optional robustness)
                else if (r_handshake && (read_index == r_burst_len))
                     r_next_state = R_DONE;
            end

            R_DONE: begin
                r_next_state = R_IDLE;
            end
        endcase
    end

    // Read Logic & Outputs
    // Capture Address on Start
    always_ff @(posedge M_AXI_ACLK) begin
        if (r_state == R_IDLE && i_m_r_start) begin
            r_base_addr <= {i_m_r_addr_hi, i_m_r_addr_lo};
            r_burst_len <= i_m_r_len[7:0];
        end
    end

    // Read Index Counter
    always_ff @(posedge M_AXI_ACLK) begin
        if (r_state == R_IDLE || r_state == R_AR_START) begin
            read_index <= 0;
        end else if (r_state == R_READ_DATA && r_handshake) begin
            read_index <= read_index + 1;
        end
    end

    // AXI Read Outputs
    assign M_AXI_ARID    = 'b0;
    assign M_AXI_ARADDR  = r_base_addr;
    assign M_AXI_ARLEN   = r_burst_len;
    assign M_AXI_ARSIZE  = clogb2((C_M_AXI_DATA_WIDTH/8)-1);
    assign M_AXI_ARBURST = 2'b01; // INCR
    assign M_AXI_ARLOCK  = 1'b0;
    assign M_AXI_ARCACHE = 4'b0010;
    assign M_AXI_ARPROT  = 3'h0;
    assign M_AXI_ARQOS   = 4'h0;

    assign M_AXI_ARVALID = (r_state == R_AR_START);

    // Read Ready: Assert only if we are in Data state AND User FIFO is not full
    assign M_AXI_RREADY  = (r_state == R_READ_DATA) && !i_rx_fifo_full;

    // FIFO Write Interface
    assign o_rx_data       = M_AXI_RDATA;
    assign o_rx_data_valid = r_handshake; // Write to FIFO when AXI valid & we accept
    assign o_rx_fifo_wen   = r_handshake;

    // User Status - Read
    always_ff @(posedge M_AXI_ACLK) begin
        if (!M_AXI_ARESETN) begin
            o_m_rxn_done <= 0;
            o_m_last_rresp <= 0;
            o_m_error <= 0;
        end else begin
            if (r_state == R_DONE) begin
                o_m_rxn_done <= 1;
                o_m_last_rresp <= M_AXI_RRESP;
            end else if (i_m_r_start) begin // Clear the “done” signal only when the next transmission begins
                o_m_rxn_done <= 0;
            end
            
            // Error Checking (Basic)
            if (r_handshake && M_AXI_RRESP[1]) // Slave Error
                o_m_error <= 1;
            else if (w_state == W_BRESP && M_AXI_BVALID && M_AXI_BRESP[1])
                o_m_error <= 1;
            else if (i_m_w_start || i_m_r_start) // Clear on new txn
                o_m_error <= 0;
        end
    end

    // -----------------------------------------------------------------
    // Instantiation of FIFO for Write Channel (TX)
    wire fwft_full;

    assign o_tx_fifo_ren = !fwft_full && (w_state == W_AW_START || w_state == W_WRITE_DATA);// w_state==W_AW_START Pre-fetch

    
    fwft_fifo #(
        .ADDR_WIDTH (2),
        .DWIDTH     (C_M_AXI_DATA_WIDTH)
    ) inst_write_channel_fifo (
        .rst_n      (M_AXI_ARESETN),
        .clk        (M_AXI_ACLK),
        
        .wr_en      (i_tx_data_valid),// from DTCore fifo i_data_valid & start_tx
        .din        (i_tx_data),// from DTCore fifo i_data
        .full       (fwft_full),// to DTCore
        
        .rd_en      (fwft_pop_en),// from read request
        .dout       (fwft_dout),// to AXI wdata
        .empty      (),// to CTRL
        .data_valid (fwft_dout_valid) // to AXI wvalid

    );

endmodule