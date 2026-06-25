`timescale 1 ns / 1 ps
// F means FIFO Version
// FIFO should be FWFT
module M_AXI_DATA #
(
	parameter integer C_M_AXI_MAX_BURST_LEN	    = 256,
	parameter integer C_M_AXI_ID_WIDTH	    = 1,
	parameter integer C_M_AXI_ADDR_WIDTH	= 64,
	parameter integer C_M_AXI_DATA_WIDTH	= 128
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
	input wire                           i_tx_data_valid, // Acts as !FIFO_EMPTY
    output wire                          o_tx_fifo_ren,   // to FIFO next data
	
	// RX FIFO Interface (Read from DDR)
	output wire	[C_M_AXI_DATA_WIDTH-1:0] o_rx_data,
	output wire                          o_rx_data_valid,
    output wire                          o_rx_fifo_wen,   // to FIFO next data
	input  wire                          i_rx_fifo_full,  // Backpressure signal

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

	localparam integer C_TRANSACTIONS_NUM = clogb2(C_M_AXI_MAX_BURST_LEN-1);

	// AXI Internal Signals
	reg  	axi_awvalid;
	reg  	axi_wvalid_req; // Internal request to send
	reg  	axi_bready;
	reg  	axi_arvalid;
	reg  	axi_rready_reg; // Internal RREADY state
	
	reg [C_TRANSACTIONS_NUM : 0] 	write_index;

	reg  	start_single_burst_write;
	reg  	start_single_burst_read;
	reg  	burst_write_active;
	reg  	burst_read_active;
	
	wire  	write_resp_error;
	wire  	read_resp_error;
	reg     read_len_err; 
	
	wire  	wnext;
	wire  	rnext;

	reg [C_M_AXI_ADDR_WIDTH-1:0] w_base_addr;
	reg [8:0]                    w_burst_len;
	reg [C_M_AXI_ADDR_WIDTH-1:0] r_base_addr;
	reg [8:0]                    r_burst_len;

	// Read Beat Counter
	reg [8:0] read_index;

	// -----------------------------------------------------------------
	// I/O Connections assignments
	// -----------------------------------------------------------------
	
	// --- Write Address ---
	assign M_AXI_AWID	= 'b0;
	// [SIMPLIFIED] No accumulation needed, just base address
	assign M_AXI_AWADDR	= w_base_addr; 
	assign M_AXI_AWLEN	= w_burst_len;
	assign M_AXI_AWSIZE	= clogb2((C_M_AXI_DATA_WIDTH/8)-1);
	assign M_AXI_AWBURST	= 2'b01; 
	assign M_AXI_AWLOCK	= 1'b0;
	assign M_AXI_AWCACHE	= 4'b0010; 
	assign M_AXI_AWPROT	= 3'h0;
	assign M_AXI_AWQOS	= 4'h0;
	assign M_AXI_AWVALID	= axi_awvalid;

	// --- Write Data ---
	assign M_AXI_WDATA	= i_tx_data;
	assign M_AXI_WSTRB	= {(C_M_AXI_DATA_WIDTH/8){1'b1}};
	assign M_AXI_WLAST = (write_index == w_burst_len) & axi_wvalid_req;
	
	// [MODIFIED] WVALID is high ONLY when internal logic is ready AND User FIFO has data
	assign M_AXI_WVALID = axi_wvalid_req & i_tx_data_valid;

    // FIFO Read enable
    assign o_tx_fifo_ren = M_AXI_WREADY & M_AXI_WVALID;

	// --- Write Response ---
	assign M_AXI_BREADY	= axi_bready;

	// --- Read Address ---
	assign M_AXI_ARID	= 'b0;
	// [SIMPLIFIED] No accumulation needed
	assign M_AXI_ARADDR	= r_base_addr;
	assign M_AXI_ARLEN	= r_burst_len;
	assign M_AXI_ARSIZE	= clogb2((C_M_AXI_DATA_WIDTH/8)-1);
	assign M_AXI_ARBURST	= 2'b01; 
	assign M_AXI_ARLOCK	= 1'b0;
	assign M_AXI_ARCACHE	= 4'b0010; 
	assign M_AXI_ARPROT	= 3'h0;
	assign M_AXI_ARQOS	= 4'h0;
	assign M_AXI_ARVALID	= axi_arvalid;

	// --- Read Data ---
	// [MODIFIED] RREADY is Low if User FIFO is Full
	assign M_AXI_RREADY	= axi_rready_reg & ~i_rx_fifo_full;

    // FIFO Write enable
    assign o_rx_fifo_wen = rnext;


	// -----------------------------------------------------------------
	// Control Logic
	// -----------------------------------------------------------------

	// Latch Params & Pulse Gen
	always @(posedge M_AXI_ACLK) begin
		if (!M_AXI_ARESETN) begin
			w_base_addr <= 'b0;
			w_burst_len <= 8'd0;
			start_single_burst_write <= 1'b0;
		end else begin
			if (i_m_w_start && ~burst_write_active) begin
				w_base_addr <= {i_m_w_addr_hi, i_m_w_addr_lo};
				w_burst_len <= i_m_w_len[7:0];
			end

			if (i_m_w_start && ~burst_write_active && ~axi_awvalid)
				start_single_burst_write <= 1'b1;
			else
				start_single_burst_write <= 1'b0;
		end
	end

	always @(posedge M_AXI_ACLK) begin
		if (!M_AXI_ARESETN) begin
			r_base_addr <= 'b0;
			r_burst_len <= 8'd0;
			start_single_burst_read <= 1'b0;
		end else begin
			if (i_m_r_start && ~burst_read_active) begin
				r_base_addr <= {i_m_r_addr_hi, i_m_r_addr_lo};
				r_burst_len <= i_m_r_len[7:0];
			end

			if (i_m_r_start && ~burst_read_active && ~axi_arvalid)
				start_single_burst_read <= 1'b1;
			else
				start_single_burst_read <= 1'b0;
		end
	end


	// --------------------
	// Write Address Channel
	// --------------------
	always @(posedge M_AXI_ACLK) begin
		if (M_AXI_ARESETN == 0) begin
			axi_awvalid <= 1'b0;
		end else if (~axi_awvalid && start_single_burst_write) begin
			axi_awvalid <= 1'b1;
		end else if (M_AXI_AWREADY && axi_awvalid) begin
			axi_awvalid <= 1'b0;
		end
	end

	// --------------------
	// Write Data Channel
	// --------------------
	
	// [MODIFIED] Handshake happens when: 
	// 1. Slave is Ready (WREADY)
	// 2. We want to send (axi_wvalid_req)
	// 3. FIFO actually has data (i_tx_data_valid)
	assign wnext = M_AXI_WREADY & axi_wvalid_req & i_tx_data_valid;

	// WVALID Request Logic
	always @(posedge M_AXI_ACLK) begin
		if (M_AXI_ARESETN == 0) begin
			axi_wvalid_req <= 1'b0;
		end else if (~axi_wvalid_req && start_single_burst_write) begin
			axi_wvalid_req <= 1'b1;
		end else if (wnext && M_AXI_WLAST) begin
			axi_wvalid_req <= 1'b0; // Done with burst
		end
	end

	// [MODIFIED] Write Index only increments on Valid Handshake (wnext)
	always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 0 || start_single_burst_write == 1'b1) begin
            write_index <= 0;
        end else if (wnext) begin
            write_index <= write_index + 1;
        end
    end

	// ----------------------------
	// Write Response (B) Channel
	// ----------------------------
	always @(posedge M_AXI_ACLK) begin
		if (M_AXI_ARESETN == 0) begin
			axi_bready <= 1'b0;
		end else if (M_AXI_BVALID && ~axi_bready) begin
			axi_bready <= 1'b1;
		end else if (axi_bready) begin
			axi_bready <= 1'b0;
		end
	end
	assign write_resp_error = axi_bready & M_AXI_BVALID & M_AXI_BRESP[1];


	// --------------------
	// Read Address Channel
	// --------------------
	always @(posedge M_AXI_ACLK) begin
		if (M_AXI_ARESETN == 0) begin
			axi_arvalid <= 1'b0;
		end else if (~axi_arvalid && start_single_burst_read) begin
			axi_arvalid <= 1'b1;
		end else if (M_AXI_ARREADY && axi_arvalid) begin
			axi_arvalid <= 1'b0;
		end
	end


	// --------------------------------
	// Read Data Channel (With Flow Control)
	// --------------------------------
	
	// [MODIFIED] rnext only true when RREADY is actually High (FIFO not full)
	assign rnext = M_AXI_RVALID && M_AXI_RREADY;

	// Internal RREADY state management
	always @(posedge M_AXI_ACLK) begin
		if (M_AXI_ARESETN == 0) begin
			axi_rready_reg <= 1'b0;
		end else begin
            // [Fix] Assert Ready immediately when burst starts to avoid deadlock
            if (start_single_burst_read) begin
                axi_rready_reg <= 1'b1;
            end
            // Handle flow control during burst
            else if (M_AXI_RVALID && axi_rready_reg) begin
                // Drop internal ready if Last beat detected (RLAST or Counter match)
                if (M_AXI_RLAST || read_index == r_burst_len) begin
                    axi_rready_reg <= 1'b0;
                end 
                // else keep it high (default)
            end
        end
	end

	// Read Index Counter
	always @(posedge M_AXI_ACLK) begin
		if (!M_AXI_ARESETN || start_single_burst_read) begin
			read_index <= 0;
		end else if (rnext) begin // Only increment on valid transfer
			read_index <= read_index + 1;
		end
	end

	// Read Error Detection
	always @(posedge M_AXI_ACLK) begin
		if (!M_AXI_ARESETN || start_single_burst_read) begin
			read_len_err <= 1'b0;
		end else if (rnext) begin
			if (M_AXI_RLAST && (read_index != r_burst_len)) 
				read_len_err <= 1'b1; // Early Termination
			else if (!M_AXI_RLAST && (read_index == r_burst_len)) 
				read_len_err <= 1'b1; // Missing RLAST
		end
	end

	// User Data Output
	assign o_rx_data = M_AXI_RDATA;
	assign o_rx_data_valid = rnext;

	assign read_resp_error = rnext & M_AXI_RRESP[1]; // Check error on valid cycle


	// --------------------------------
	// Throttle / Active Flags
	// --------------------------------
	
	always @(posedge M_AXI_ACLK) begin
		if (M_AXI_ARESETN == 0) 
			burst_write_active <= 1'b0;
		else if (start_single_burst_write) 
			burst_write_active <= 1'b1;
		else if (M_AXI_BVALID && axi_bready) 
			burst_write_active <= 0;
	end

	always @(posedge M_AXI_ACLK) begin
		if (M_AXI_ARESETN == 0) 
			burst_read_active <= 1'b0;
		else if (start_single_burst_read) 
			burst_read_active <= 1'b1;
		// End on RLAST or Count Match (using rnext to ensure sync)
		else if (rnext && (M_AXI_RLAST || read_index == r_burst_len)) 
			burst_read_active <= 0;
	end

	// --------------------------------
	// User Done / Status Signals
	// --------------------------------
	always @(posedge M_AXI_ACLK) begin
		if (!M_AXI_ARESETN) begin
			o_m_txn_done   <= 1'b0;
			o_m_last_bresp <= 2'b00;
		end else begin
			if (i_m_w_start && ~burst_write_active) 
				o_m_txn_done <= 1'b0;
			if (M_AXI_BVALID && axi_bready) begin
				o_m_last_bresp <= M_AXI_BRESP;
				o_m_txn_done   <= 1'b1;
			end
		end
	end

	always @(posedge M_AXI_ACLK) begin
		if (!M_AXI_ARESETN) begin
			o_m_rxn_done   <= 1'b0;
			o_m_last_rresp <= 2'b00;
		end else begin
			if (i_m_r_start && ~burst_read_active) 
				o_m_rxn_done <= 1'b0;
			
			if (rnext && (M_AXI_RLAST || read_index == r_burst_len)) begin
				o_m_last_rresp <= M_AXI_RRESP;
				o_m_rxn_done   <= 1'b1;
			end
		end
	end

	// Error output
	always @(posedge M_AXI_ACLK) begin
		if (!M_AXI_ARESETN) begin
			o_m_error <= 1'b0;
		end else if (write_resp_error || read_resp_error || read_len_err) begin
			o_m_error <= 1'b1;
		end
	end

endmodule