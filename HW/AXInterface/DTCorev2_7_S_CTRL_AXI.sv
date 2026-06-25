`timescale 1 ns / 1 ps

	module DTCorev2_7_S_CTRL_AXI #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line

		// Width of S_AXI data bus
		parameter integer C_S_AXI_DATA_WIDTH	= 32,
		// Width of S_AXI address bus
		parameter integer C_S_AXI_ADDR_WIDTH	= 12
	)
	(
		// Users to add ports here
		input  wire        i_core_idle,
		input  wire        i_any_tilewb_full,
		input  wire        i_error_tile_wb_conflict,
		input  wire        i_error_op,

		input  wire [1:0]  i_agu_slot_ready [3:0],
		input  wire [1:0]  i_agu_slot_busy [3:0],
		input  wire [3:0]  i_core_busy,
		input  wire [3:0]  i_tile_busy,

		input  wire [5:0]  i_inst_status [3:0],

		// To DTCore 
		output wire o_dtc_en,
		output wire o_soft_rst,
		output wire o_irq_en,
		output wire o_ext_busy,
		output wire o_irq,

		// To issue
		output wire [2:0] o_issue_type, //one-shout, not in wb, auto

		// from Data/IFB FIFO
		input  wire        i_ifb_empty,
		input  wire        i_ifb_full,
		input  wire [7:0]  i_ifb_level,
		input  wire [127:0]i_ifb_data, //instruction

		input  wire [3:0]  i_idb_empty,
		input  wire [3:0]  i_idb_full,
		input  wire [7:0]  i_idb_level [3:0],

		input  wire        i_odb_empty,
		input  wire        i_odb_full,

		// To Data/IFB FIFO
		output wire        o_ifb_r_en,
		output wire [3:0]  o_idb_r_en,

		// from Master
		input  wire        i_m_txn_done,
		input  wire        i_m_rxn_done,
		input  wire        i_m_error,
		input  wire [1:0]  i_last_bresp,
		input  wire [1:0]  i_last_rresp,

		//To Master
		output wire o_m_w_start,
		output wire o_m_r_start,

		output wire [31:0] o_m_w_addr_lo,
		output wire [31:0] o_m_w_addr_hi,
		output wire [31:0] o_m_w_len,
		output wire [31:0] o_m_r_addr_lo,
		output wire [31:0] o_m_r_addr_hi,
		output wire [31:0] o_m_r_len,

		// Control Master throttle/ Target
		output reg         o_throttle_inst,     
		output reg [3:0]   o_throttle_idb,      
		output wire        o_dst_sel_inst,      
		output wire [1:0]  o_dst_data_port, 

		output wire [1:0]  o_thread_id [3:0],
		// User ports ends
		// Do not modify the ports beyond this line

		// Global Clock Signal
		input wire  S_AXI_ACLK,
		// Global Reset Signal. This Signal is Active LOW
		input wire  S_AXI_ARESETN,
		// Write address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
		// Write channel Protection type. This signal indicates the
    		// privilege and security level of the transaction, and whether
    		// the transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_AWPROT,
		// Write address valid. This signal indicates that the master signaling
    		// valid write address and control information.
		input wire  S_AXI_AWVALID,
		// Write address ready. This signal indicates that the slave is ready
    		// to accept an address and associated control signals.
		output wire  S_AXI_AWREADY,
		// Write data (issued by master, acceped by Slave) 
		input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
		// Write strobes. This signal indicates which byte lanes hold
    		// valid data. There is one write strobe bit for each eight
    		// bits of the write data bus.    
		input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
		// Write valid. This signal indicates that valid write
    		// data and strobes are available.
		input wire  S_AXI_WVALID,
		// Write ready. This signal indicates that the slave
    		// can accept the write data.
		output wire  S_AXI_WREADY,
		// Write response. This signal indicates the status
    		// of the write transaction.
		output wire [1 : 0] S_AXI_BRESP,
		// Write response valid. This signal indicates that the channel
    		// is signaling a valid write response.
		output wire  S_AXI_BVALID,
		// Response ready. This signal indicates that the master
    		// can accept a write response.
		input wire  S_AXI_BREADY,
		// Read address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
		// Protection type. This signal indicates the privilege
    		// and security level of the transaction, and whether the
    		// transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_ARPROT,
		// Read address valid. This signal indicates that the channel
    		// is signaling valid read address and control information.
		input wire  S_AXI_ARVALID,
		// Read address ready. This signal indicates that the slave is
    		// ready to accept an address and associated control signals.
		output wire  S_AXI_ARREADY,
		// Read data (issued by slave)
		output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
		// Read response. This signal indicates the status of the
    		// read transfer.
		output wire [1 : 0] S_AXI_RRESP,
		// Read valid. This signal indicates that the channel is
    		// signaling the required read data.
		output wire  S_AXI_RVALID,
		// Read ready. This signal indicates that the master can
    		// accept the read data and response information.
		input wire  S_AXI_RREADY
	);

	// AXI4LITE signals
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
	reg  	axi_awready;
	reg  	axi_wready;
	reg [1 : 0] 	axi_bresp;
	reg  	axi_bvalid;
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
	reg  	axi_arready;
	reg [C_S_AXI_DATA_WIDTH-1 : 0] 	axi_rdata;
	reg [1 : 0] 	axi_rresp;
	reg  	axi_rvalid;

	// Example-specific design signals
	// local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	// ADDR_LSB is used for addressing 32/64 bit registers/memories
	// ADDR_LSB = 2 for 32 bits (n downto 2)
	// ADDR_LSB = 3 for 64 bits (n downto 3)
	localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
	localparam integer CSR_ADDR_BITS = 8;

	// Address Mapping (Word aligned index)
    localparam [CSR_ADDR_BITS-1:0] CSR_CTRL         = 8'h00; // 0x000
    localparam [CSR_ADDR_BITS-1:0] CSR_STATUS_CORE_0 = 8'h01; // 0x004
	localparam [CSR_ADDR_BITS-1:0] CSR_STATUS_CORE_1 = 8'h02; // 0x008
    localparam [CSR_ADDR_BITS-1:0] CSR_STATUS_FIFO  = 8'h03; // 0x00C
    localparam [CSR_ADDR_BITS-1:0] CSR_STATUS_MST   = 8'h04; // 0x010
    localparam [CSR_ADDR_BITS-1:0] CSR_ERR          = 8'h05; // 0x014
    localparam [CSR_ADDR_BITS-1:0] CSR_ISR          = 8'h06; // 0x018 Interrupt Status
    localparam [CSR_ADDR_BITS-1:0] CSR_IER          = 8'h07; // 0x01C Interrupt Enable

    localparam [CSR_ADDR_BITS-1:0] CSR_WM_IFB_HI    = 8'h40; // 0x100
    localparam [CSR_ADDR_BITS-1:0] CSR_WM_IFB_LO    = 8'h41; // 0x104
    localparam [CSR_ADDR_BITS-1:0] CSR_WM_IDB0_HI   = 8'h42; // 0x108
    localparam [CSR_ADDR_BITS-1:0] CSR_WM_IDB0_LO   = 8'h43; // 0x10C
    localparam [CSR_ADDR_BITS-1:0] CSR_WM_IDB1_HI   = 8'h44; // 0x110
    localparam [CSR_ADDR_BITS-1:0] CSR_WM_IDB1_LO   = 8'h45; // 0x114
    localparam [CSR_ADDR_BITS-1:0] CSR_WM_IDB2_HI   = 8'h46; // 0x118
    localparam [CSR_ADDR_BITS-1:0] CSR_WM_IDB2_LO   = 8'h47; // 0x11C
    localparam [CSR_ADDR_BITS-1:0] CSR_WM_IDB3_HI   = 8'h48; // 0x120
    localparam [CSR_ADDR_BITS-1:0] CSR_WM_IDB3_LO   = 8'h49; // 0x124

    localparam [CSR_ADDR_BITS-1:0] CSR_TRACE_INST0  = 8'hA0; // 0x280
    localparam [CSR_ADDR_BITS-1:0] CSR_TRACE_INST1  = 8'hA1; // 0x284
    localparam [CSR_ADDR_BITS-1:0] CSR_TRACE_INST2  = 8'hA2; // 0x288
    localparam [CSR_ADDR_BITS-1:0] CSR_TRACE_INST3  = 8'hA3; // 0x28C

    localparam [CSR_ADDR_BITS-1:0] CSR_MS_W_ADDR_LO = 8'hC0; // 0x300
    localparam [CSR_ADDR_BITS-1:0] CSR_MS_W_ADDR_HI = 8'hC1; // 0x304
    localparam [CSR_ADDR_BITS-1:0] CSR_MS_W_LEN     = 8'hC2; // 0x308
    localparam [CSR_ADDR_BITS-1:0] CSR_MS_R_ADDR_LO = 8'hC4; // 0x310
    localparam [CSR_ADDR_BITS-1:0] CSR_MS_R_ADDR_HI = 8'hC5; // 0x314
    localparam [CSR_ADDR_BITS-1:0] CSR_MS_R_LEN     = 8'hC6; // 0x318

	//----------------------------------------------
	//-- Signals for user logic register space example
	//------------------------------------------------
	reg [31:0] csr_ctrl;
    reg [31:0] csr_status_core_0;
	reg [31:0] csr_status_core_1;
    reg [31:0] csr_status_fifo;
    reg [31:0] csr_status_master;
    reg [31:0] csr_err;

    reg [31:0] csr_isr;
    reg [31:0] csr_ier;

    reg [31:0] csr_wm_ifb_hi;
    reg [31:0] csr_wm_ifb_lo;
    reg [31:0] csr_wm_idb_hi [3:0];
    reg [31:0] csr_wm_idb_lo [3:0];

    reg [127:0] csr_trace_inst;

    reg [31:0] csr_ms_w_addr_lo;
    reg [31:0] csr_ms_w_addr_hi;
    reg [31:0] csr_ms_w_len;
    reg [31:0] csr_ms_r_addr_lo;
    reg [31:0] csr_ms_r_addr_hi;
    reg [31:0] csr_ms_r_len;

	// Control Pulse Signals
    reg  rd_start_pulse, wr_start_pulse;

	// Helper signals for decoding
	wire	 slv_reg_rden;
	wire	 slv_reg_wren;
	reg	 	 aw_en;

	// I/O Connections assignments
	assign S_AXI_AWREADY	= axi_awready;
	assign S_AXI_WREADY		= axi_wready;
	assign S_AXI_BRESP		= axi_bresp;
	assign S_AXI_BVALID		= axi_bvalid;
	assign S_AXI_ARREADY	= axi_arready;
	assign S_AXI_RDATA		= axi_rdata;
	assign S_AXI_RRESP		= axi_rresp;
	assign S_AXI_RVALID		= axi_rvalid;

	// ------------------------------------------------------------------------
    // AXI4-Lite Control State Machine (Standard Template from v2_7)
    // ------------------------------------------------------------------------

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_awready <= 1'b0;
	      aw_en <= 1'b1;
	    end 
	  else
	    begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
	        begin
	          // slave is ready to accept write address when 
	          // there is a valid write address and write data
	          // on the write address and data bus. This design 
	          // expects no outstanding transactions. 
	          axi_awready <= 1'b1;
	          aw_en <= 1'b0;
	        end
	        else if (S_AXI_BREADY && axi_bvalid)
	            begin
	              aw_en <= 1'b1;
	              axi_awready <= 1'b0;
	            end
	      else           
	        begin
	          axi_awready <= 1'b0;
	        end
	    end 
	end       

	// Implement axi_awaddr latching
	// This process is used to latch the address when both 
	// S_AXI_AWVALID and S_AXI_WVALID are valid. 

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_awaddr <= 0;
	    end 
	  else
	    begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
	        begin
	          // Write Address latching 
	          axi_awaddr <= S_AXI_AWADDR;
	        end
	    end 
	end       

	// Implement axi_wready generation
	// axi_wready is asserted for one S_AXI_ACLK clock cycle when both
	// S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is 
	// de-asserted when reset is low. 

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_wready <= 1'b0;
	    end 
	  else
	    begin    
	      if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en )
	        begin
	          // slave is ready to accept write data when 
	          // there is a valid write address and write data
	          // on the write address and data bus. This design 
	          // expects no outstanding transactions. 
	          axi_wready <= 1'b1;
	        end
	      else
	        begin
	          axi_wready <= 1'b0;
	        end
	    end 
	end       
  

	// Implement write response logic generation
	// The write response and response valid signals are asserted by the slave 
	// when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.  
	// This marks the acceptance of address and indicates the status of 
	// write transaction.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_bvalid  <= 0;
	      axi_bresp   <= 2'b0;
	    end 
	  else
	    begin    
	      if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID)
	        begin
	          // indicates a valid write response is available
	          axi_bvalid <= 1'b1;
	          axi_bresp  <= 2'b0; // 'OKAY' response 
	        end                   // work error responses in future
	      else
	        begin
	          if (S_AXI_BREADY && axi_bvalid) 
	            //check if bready is asserted while bvalid is high) 
	            //(there is a possibility that bready is always asserted high)   
	            begin
	              axi_bvalid <= 1'b0; 
	            end  
	        end
	    end
	end   

	// Implement axi_arready generation
	// axi_arready is asserted for one S_AXI_ACLK clock cycle when
	// S_AXI_ARVALID is asserted. axi_awready is 
	// de-asserted when reset (active low) is asserted. 
	// The read address is also latched when S_AXI_ARVALID is 
	// asserted. axi_araddr is reset to zero on reset assertion.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_arready <= 1'b0;
	      axi_araddr  <= 32'b0;
	    end 
	  else
	    begin    
	      if (~axi_arready && S_AXI_ARVALID)
	        begin
	          // indicates that the slave has acceped the valid read address
	          axi_arready <= 1'b1;
	          // Read address latching
	          axi_araddr  <= S_AXI_ARADDR;
	        end
	      else
	        begin
	          axi_arready <= 1'b0;
	        end
	    end 
	end       

	// Implement axi_arvalid generation
	// axi_rvalid is asserted for one S_AXI_ACLK clock cycle when both 
	// S_AXI_ARVALID and axi_arready are asserted. The slave registers 
	// data are available on the axi_rdata bus at this instance. The 
	// assertion of axi_rvalid marks the validity of read data on the 
	// bus and axi_rresp indicates the status of read transaction.axi_rvalid 
	// is deasserted on reset (active low). axi_rresp and axi_rdata are 
	// cleared to zero on reset (active low).  
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_rvalid <= 0;
	      axi_rresp  <= 0;
	    end 
	  else
	    begin    
	      if (axi_arready && S_AXI_ARVALID && ~axi_rvalid)
	        begin
	          // Valid read data is available at the read data bus
	          axi_rvalid <= 1'b1;
	          axi_rresp  <= 2'b0; // 'OKAY' response
	        end   
	      else if (axi_rvalid && S_AXI_RREADY)
	        begin
	          // Read data is accepted by the master
	          axi_rvalid <= 1'b0;
	        end                
	    end
	end    

	// Implement memory mapped register select and read logic generation
	// Slave register read enable is asserted when valid address is available
	// and the slave is ready to accept the read address.
	assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID; 

	wire [CSR_ADDR_BITS-1:0] wr_addr_index = axi_awaddr[ADDR_LSB + CSR_ADDR_BITS - 1 : ADDR_LSB];

	// Special Write Logic Helpers
    wire sel_ctrl = (wr_addr_index == CSR_CTRL);
    wire sel_isr  = (wr_addr_index == CSR_ISR);
    wire sel_ier  = (wr_addr_index == CSR_IER);
    wire sel_err  = (wr_addr_index == CSR_ERR);
    
    wire [31:0] wmask = sel_err ? S_AXI_WDATA : 32'h0;
    wire [31:0] sw_clr_mask = (slv_reg_wren && sel_err) ? wmask : 32'h0;


	// 1. CSR_CTRL and Start Pulses
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            csr_ctrl            <= 32'h0;
            rd_start_pulse      <= 1'b0;
            wr_start_pulse      <= 1'b0;
        end else begin
            rd_start_pulse      <= 1'b0;
            wr_start_pulse      <= 1'b0;
            
            if (slv_reg_wren && sel_ctrl) begin
                csr_ctrl[3:0]   <= S_AXI_WDATA[3:0];     // enable, soft_reset, intr_en, ext_busy
                csr_ctrl[6:4]   <= S_AXI_WDATA[6:4];     // issue type
                csr_ctrl[16:7]  <= S_AXI_WDATA[16:7];    // rd/wr 
                csr_ctrl[27:21] <= S_AXI_WDATA[27:20];   // thread_id

                // Pulse Generation
                if (S_AXI_WDATA[7])  rd_start_pulse <= 1'b1; 
                if (S_AXI_WDATA[13]) wr_start_pulse <= 1'b1;
            end

            // soft_reset self clear
            if (csr_ctrl[1]) begin
                csr_ctrl[1] <= 1'b0;
            end

			// 
			if (!csr_ctrl[3]) begin
				csr_ctrl[3] <= 1'b0;
			end

        end
    end

    // 2. Error Register
    wire hw_wb_conflict     = i_error_tile_wb_conflict;
    wire hw_axi_wr_resp_err = i_last_bresp[1]; // BRESP != OKAY
    wire hw_axi_rd_resp_err = i_last_rresp[1]; // RRESP != OKAY
    wire hw_op_error        = i_error_op;

    wire [31:0] hw_err_set = {
        27'd0,
        1'b0,               // bit4: reserved 
        hw_axi_rd_resp_err, // bit3
        hw_axi_wr_resp_err, // bit2
        hw_wb_conflict,     // bit1
        hw_op_error         // bit0: Opcode Error
    };

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            csr_err <= 32'h0;
        end else begin
            csr_err <= csr_err | hw_err_set;
            if (|sw_clr_mask)
                csr_err <= (csr_err | hw_err_set) & ~sw_clr_mask;
        end
    end

    // 3. Interrupt Status Register (ISR) & Enable Register (IER)
    // Bit 0: Opcode Error      (Aligned with CSR_ERR)
    // Bit 1: Tile WB Conflict  (Aligned with CSR_ERR)
    // Bit 2: AXI Error (Any)   
    // Bit 3: TX Done
    // Bit 4: RX Done
    // Bit 5: IFB Low (Watermark)
    // Bit 6: IDB Low (Watermark)
    // Bit 7: ODB Full
    wire isr_axi_err = hw_axi_rd_resp_err | hw_axi_wr_resp_err | i_m_error;

    // Buffer Interrupt Conditions
    wire ifb_low = (i_ifb_level <= csr_wm_ifb_lo[7:0]);
    
    reg any_idb_low;
    integer k_isr;
    always @(*) begin
        any_idb_low = 1'b0;
        for(k_isr=0; k_isr<4; k_isr=k_isr+1) begin
            if (i_idb_level[k_isr] <= csr_wm_idb_lo[k_isr][7:0])
                any_idb_low = 1'b1;
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            csr_isr <= 32'h0;
            csr_ier <= 32'h0;
        end else begin
            // 1. Write 1 to Clear (W1C) - Prioritize Clear
            if (slv_reg_wren && sel_isr) begin
                csr_isr <= csr_isr & ~S_AXI_WDATA;
            end

            // 2. Capture Events (Sticky) - Hardware Wins (Overrides Clear if concurrent)

			csr_isr[0] <= hw_op_error; // Opcode error is sticky until cleared by software, regardless of new errors
			csr_isr[1] <= hw_wb_conflict;
			csr_isr[2] <= isr_axi_err;
			csr_isr[3] <= i_m_txn_done;
			csr_isr[4] <= i_m_rxn_done;
			csr_isr[5] <= ifb_low;
			csr_isr[6] <= any_idb_low;
			csr_isr[7] <= i_odb_full;

            // Write IER
            if (slv_reg_wren && sel_ier) begin
                csr_ier <= S_AXI_WDATA;
            end
        end
    end

    assign o_irq = |(csr_isr & csr_ier);

    // 4. Other Writable CSRs (Watermarks & Master Config)
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            csr_wm_ifb_hi    <= 32'd128;
            csr_wm_ifb_lo    <= 32'd64;
            csr_wm_idb_hi[0] <= 32'd128;
            csr_wm_idb_lo[0] <= 32'd64;
            csr_wm_idb_hi[1] <= 32'd128;
            csr_wm_idb_lo[1] <= 32'd64;
            csr_wm_idb_hi[2] <= 32'd128;
            csr_wm_idb_lo[2] <= 32'd64;
            csr_wm_idb_hi[3] <= 32'd128;
            csr_wm_idb_lo[3] <= 32'd64;

            csr_ms_w_addr_lo <= 32'd0;
            csr_ms_w_addr_hi <= 32'd0;
            csr_ms_w_len     <= 32'd0;
            csr_ms_r_addr_lo <= 32'd0;
            csr_ms_r_addr_hi <= 32'd0;
            csr_ms_r_len     <= 32'd0;
        end else if (slv_reg_wren) begin
            case (wr_addr_index)
                CSR_WM_IFB_HI:  csr_wm_ifb_hi    <= S_AXI_WDATA;
                CSR_WM_IFB_LO:  csr_wm_ifb_lo    <= S_AXI_WDATA;
                CSR_WM_IDB0_HI: csr_wm_idb_hi[0] <= S_AXI_WDATA;
                CSR_WM_IDB0_LO: csr_wm_idb_lo[0] <= S_AXI_WDATA;
                CSR_WM_IDB1_HI: csr_wm_idb_hi[1] <= S_AXI_WDATA;
                CSR_WM_IDB1_LO: csr_wm_idb_lo[1] <= S_AXI_WDATA;
                CSR_WM_IDB2_HI: csr_wm_idb_hi[2] <= S_AXI_WDATA;
                CSR_WM_IDB2_LO: csr_wm_idb_lo[2] <= S_AXI_WDATA;
                CSR_WM_IDB3_HI: csr_wm_idb_hi[3] <= S_AXI_WDATA;
                CSR_WM_IDB3_LO: csr_wm_idb_lo[3] <= S_AXI_WDATA;
                
                CSR_MS_W_ADDR_LO:csr_ms_w_addr_lo <= S_AXI_WDATA;
                CSR_MS_W_ADDR_HI:csr_ms_w_addr_hi <= S_AXI_WDATA;
                CSR_MS_W_LEN:    csr_ms_w_len     <= S_AXI_WDATA;
                CSR_MS_R_ADDR_LO:csr_ms_r_addr_lo <= S_AXI_WDATA;
                CSR_MS_R_ADDR_HI:csr_ms_r_addr_hi <= S_AXI_WDATA;
                CSR_MS_R_LEN:    csr_ms_r_len     <= S_AXI_WDATA;
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // [INTEGRATION] Read Logic (Ported from v2_4)
    // ------------------------------------------------------------------------
    
    assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;

    wire [CSR_ADDR_BITS-1:0] rd_addr_index = axi_araddr[ADDR_LSB + CSR_ADDR_BITS - 1 : ADDR_LSB];
    reg [C_S_AXI_DATA_WIDTH-1:0]	 reg_data_out;

    always @(*) begin
        case (rd_addr_index)
            CSR_CTRL:          reg_data_out = csr_ctrl;
            CSR_STATUS_CORE_0: reg_data_out = csr_status_core_0;
			CSR_STATUS_CORE_1: reg_data_out = csr_status_core_1;
            CSR_STATUS_FIFO: reg_data_out = csr_status_fifo;
            CSR_STATUS_MST:  reg_data_out = csr_status_master;
            CSR_ERR:         reg_data_out = csr_err;
            CSR_ISR:         reg_data_out = csr_isr;
            CSR_IER:         reg_data_out = csr_ier;
            
            CSR_WM_IFB_HI:   reg_data_out = csr_wm_ifb_hi;
            CSR_WM_IFB_LO:   reg_data_out = csr_wm_ifb_lo;
            CSR_WM_IDB0_HI:  reg_data_out = csr_wm_idb_hi[0];
            CSR_WM_IDB0_LO:  reg_data_out = csr_wm_idb_lo[0];
            CSR_WM_IDB1_HI:  reg_data_out = csr_wm_idb_hi[1];
            CSR_WM_IDB1_LO:  reg_data_out = csr_wm_idb_lo[1];
            CSR_WM_IDB2_HI:  reg_data_out = csr_wm_idb_hi[2];
            CSR_WM_IDB2_LO:  reg_data_out = csr_wm_idb_lo[2];
            CSR_WM_IDB3_HI:  reg_data_out = csr_wm_idb_hi[3];
            CSR_WM_IDB3_LO:  reg_data_out = csr_wm_idb_lo[3];

            CSR_TRACE_INST0: reg_data_out = csr_trace_inst[31:0];
            CSR_TRACE_INST1: reg_data_out = csr_trace_inst[63:32];
            CSR_TRACE_INST2: reg_data_out = csr_trace_inst[95:64];
            CSR_TRACE_INST3: reg_data_out = csr_trace_inst[127:96];

            CSR_MS_W_ADDR_LO:reg_data_out = csr_ms_w_addr_lo;
            CSR_MS_W_ADDR_HI:reg_data_out = csr_ms_w_addr_hi;
            CSR_MS_W_LEN:    reg_data_out = csr_ms_w_len;
            CSR_MS_R_ADDR_LO:reg_data_out = csr_ms_r_addr_lo;
            CSR_MS_R_ADDR_HI:reg_data_out = csr_ms_r_addr_hi;
            CSR_MS_R_LEN:    reg_data_out = csr_ms_r_len;
            default:         reg_data_out = 32'h0;
        endcase
    end

	// Output register or memory read data
    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            axi_rdata  <= 0;
        end else begin    
            if (slv_reg_rden) begin
                axi_rdata <= reg_data_out;
            end   
        end
    end    

    // ------------------------------------------------------------------------
    // [INTEGRATION] Functional Logic (Status, Trace, Throttling)
    // ------------------------------------------------------------------------

    // Status Registers Update
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            csr_status_core_0 <= 32'h0;
			csr_status_core_1 <= 32'h0;
            csr_status_fifo <= 32'h0;
            csr_status_master <= 32'h0;
        end else begin
            csr_status_core_0[0]   <= i_core_idle;
            csr_status_core_0[1]   <= i_any_tilewb_full;
            csr_status_core_0[9:2] <= {i_agu_slot_ready[3],i_agu_slot_ready[2],i_agu_slot_ready[1],i_agu_slot_ready[0]};
            csr_status_core_0[17:10] <= {i_agu_slot_busy[3],i_agu_slot_busy[2],i_agu_slot_busy[1],i_agu_slot_busy[0]};
			csr_status_core_0[21:18] <= i_core_busy;
			csr_status_core_0[25:22] <= i_tile_busy;

			csr_status_core_1[23:0] <= {i_inst_status[3], i_inst_status[2], i_inst_status[1], i_inst_status[0]};

            csr_status_fifo[0]   <= i_ifb_empty;
            csr_status_fifo[1]   <= i_ifb_full;
            csr_status_fifo[5:2] <= i_idb_empty;
			csr_status_fifo[9:6] <= i_idb_full;
			csr_status_fifo[10]  <= i_odb_empty;
			csr_status_fifo[11]  <= i_odb_full;

            csr_status_master[0]   <= i_m_txn_done;
			csr_status_master[1]   <= i_m_rxn_done;
            csr_status_master[2]   <= i_m_error;
            csr_status_master[4:3] <= i_last_bresp;
            csr_status_master[6:5] <= i_last_rresp;
        end
    end

    // Trace Inst (Simplistic mapping)
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
             csr_trace_inst <= 128'd0;
        end else begin
             // Typically this would capture on some trigger, 
             // here we just mirror the input if available or keep existing logic
             // Assuming simply capturing current IFB data for debug
             csr_trace_inst <= i_ifb_data; 
        end
    end

    // Throttling Logic
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            o_throttle_inst <= 1'b0;
            o_throttle_idb  <= 4'b0;
        end else begin
            // IFB
            if (i_ifb_level >= csr_wm_ifb_hi[7:0])
                o_throttle_inst <= 1'b1;
            else if (i_ifb_level <= csr_wm_ifb_lo[7:0])
                o_throttle_inst <= 1'b0;
            
            // IDB
            for(integer k=0; k<4; k=k+1) begin
                if (i_idb_level[k] >= csr_wm_idb_hi[k][7:0])
                    o_throttle_idb[k] <= 1'b1;
                else if (i_idb_level[k] <= csr_wm_idb_lo[k][7:0])
                    o_throttle_idb[k] <= 1'b0;
            end
        end
    end

    // Output Assignments
    assign o_dtc_en   = csr_ctrl[0];
    assign o_soft_rst = csr_ctrl[1];
    assign o_irq_en   = csr_ctrl[2];
	assign o_ext_busy = csr_ctrl[3];

    assign o_m_w_addr_lo = csr_ms_w_addr_lo;
    assign o_m_w_addr_hi = csr_ms_w_addr_hi;
    assign o_m_w_len     = csr_ms_w_len;
    assign o_m_r_addr_lo = csr_ms_r_addr_lo;
    assign o_m_r_addr_hi = csr_ms_r_addr_hi;
    assign o_m_r_len     = csr_ms_r_len;

    assign o_issue_type = csr_ctrl[6:4];
    assign o_m_w_start  = wr_start_pulse;
    assign o_m_r_start  = rd_start_pulse;

    assign o_dst_sel_inst  = csr_ctrl[14];   
    assign o_dst_data_port = csr_ctrl[16:15];

	assign o_ifb_r_en = csr_ctrl[8];
	assign o_idb_r_en = csr_ctrl[12:9];

	assign o_thread_id[0] = csr_ctrl[21:20];
	assign o_thread_id[1] = csr_ctrl[23:22];
	assign o_thread_id[2] = csr_ctrl[25:24];
	assign o_thread_id[3] = csr_ctrl[27:26];

	endmodule
