`timescale 1 ns / 1 ps
// Version v2.7
	module DTCore_Top #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S_CTRL_AXI
		parameter integer C_S_CTRL_AXI_DATA_WIDTH	= 32,
		parameter integer C_S_CTRL_AXI_ADDR_WIDTH	= 12,

		// Parameters of Axi Master Bus Interface M_AXI_DATA
		parameter integer C_M_AXI_DATA_MAX_BURST_LEN = 256,
		parameter integer C_M_AXI_DATA_ID_WIDTH	    = 1,
		parameter integer C_M_AXI_DATA_ADDR_WIDTH	= 64,
		parameter integer C_M_AXI_DATA_DATA_WIDTH	= 128
	)
	(
		// Users to add ports here
		input wire clk,
		input wire rst_n,
		output wire o_irq,
		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Slave Bus Interface S_CTRL_AXI
		input wire  s_ctrl_axi_aclk,
		input wire  s_ctrl_axi_aresetn,
		input wire [C_S_CTRL_AXI_ADDR_WIDTH-1 : 0] s_ctrl_axi_awaddr,
		input wire [2 : 0] s_ctrl_axi_awprot,
		input wire  s_ctrl_axi_awvalid,
		output wire  s_ctrl_axi_awready,
		input wire [C_S_CTRL_AXI_DATA_WIDTH-1 : 0] s_ctrl_axi_wdata,  
		input wire [(C_S_CTRL_AXI_DATA_WIDTH/8)-1 : 0] s_ctrl_axi_wstrb,
		input wire  s_ctrl_axi_wvalid,
		output wire  s_ctrl_axi_wready,
		output wire [1 : 0] s_ctrl_axi_bresp,
		output wire  s_ctrl_axi_bvalid,
		input wire  s_ctrl_axi_bready,
		input wire [C_S_CTRL_AXI_ADDR_WIDTH-1 : 0] s_ctrl_axi_araddr,
		input wire [2 : 0] s_ctrl_axi_arprot,
		input wire  s_ctrl_axi_arvalid,
		output wire  s_ctrl_axi_arready,
		output wire [C_S_CTRL_AXI_DATA_WIDTH-1 : 0] s_ctrl_axi_rdata,
		output wire [1 : 0] s_ctrl_axi_rresp,
		output wire  s_ctrl_axi_rvalid,
		input wire  s_ctrl_axi_rready,

		// Ports of Axi Master Bus Interface M_AXI_DATA

		input wire  m_axi_data_aclk,
		input wire  m_axi_data_aresetn,
		output wire [C_M_AXI_DATA_ID_WIDTH-1 : 0] m_axi_data_awid,
		output wire [C_M_AXI_DATA_ADDR_WIDTH-1 : 0] m_axi_data_awaddr,
		output wire [7 : 0] m_axi_data_awlen,
		output wire [2 : 0] m_axi_data_awsize,
		output wire [1 : 0] m_axi_data_awburst,
		output wire  m_axi_data_awlock,
		output wire [3 : 0] m_axi_data_awcache,
		output wire [2 : 0] m_axi_data_awprot,
		output wire [3 : 0] m_axi_data_awqos,
		output wire  m_axi_data_awvalid,
		input wire  m_axi_data_awready,
		output wire [C_M_AXI_DATA_DATA_WIDTH-1 : 0] m_axi_data_wdata,
		output wire [C_M_AXI_DATA_DATA_WIDTH/8-1 : 0] m_axi_data_wstrb,
		output wire  m_axi_data_wlast,
		output wire  m_axi_data_wvalid,
		input wire  m_axi_data_wready,
		input wire [C_M_AXI_DATA_ID_WIDTH-1 : 0] m_axi_data_bid,
		input wire [1 : 0] m_axi_data_bresp,
		input wire  m_axi_data_bvalid,
		output wire  m_axi_data_bready,
		output wire [C_M_AXI_DATA_ID_WIDTH-1 : 0] m_axi_data_arid,
		output wire [C_M_AXI_DATA_ADDR_WIDTH-1 : 0] m_axi_data_araddr,
		output wire [7 : 0] m_axi_data_arlen,
		output wire [2 : 0] m_axi_data_arsize,
		output wire [1 : 0] m_axi_data_arburst,
		output wire  m_axi_data_arlock,
		output wire [3 : 0] m_axi_data_arcache,
		output wire [2 : 0] m_axi_data_arprot,
		output wire [3 : 0] m_axi_data_arqos,
		output wire  m_axi_data_arvalid,
		input wire  m_axi_data_arready,
		input wire [C_M_AXI_DATA_ID_WIDTH-1 : 0] m_axi_data_rid,
		input wire [C_M_AXI_DATA_DATA_WIDTH-1 : 0] m_axi_data_rdata,
		input wire [1 : 0] m_axi_data_rresp,
		input wire  m_axi_data_rlast,
		input wire  m_axi_data_rvalid,
		output wire  m_axi_data_rready
	);


		wire  	   	core_idle;
		assign core_idle =1; //Auto start , must 

		wire  	   	any_tilewb_full;
		wire [3:0] tilewb_fifo_full;
		assign any_tilewb_full = |tilewb_fifo_full;

		wire  	   	any_error_tile_wb_conflict;
		wire [3:0] error_tile_wb_conflict;
		assign any_error_tile_wb_conflict = |error_tile_wb_conflict;

		wire        any_error_op;
		wire [3:0]  error_op;
		assign any_error_op = |error_op;

		wire [3:0] 	agu_busy_vec;
		wire [3:0] 	agu_ready_vec;
		wire [1:0]  agu_slot_ready [3:0];
		wire [1:0]  agu_slot_busy [3:0];		

		wire        dtc_en;
		wire        soft_rst;
		wire        irq_en;
		wire [2:0]  issue_type;

		wire        m_w_start;
		wire        m_r_start;
		wire [31:0] m_w_addr_lo;
		wire [31:0] m_w_addr_hi;
		wire [31:0] m_w_len;
		wire [31:0] m_r_addr_lo;
		wire [31:0] m_r_addr_hi;
		wire [31:0] m_r_len;

		wire        m_txn_done;
		wire        m_rxn_done;
		wire        m_error;
		wire [1:0]  m_last_bresp;
		wire [1:0]  m_last_rresp;

		wire [C_M_AXI_DATA_DATA_WIDTH-1 : 0] tx_data;
		wire tx_data_valid;
		wire tx_fifo_rd_en;

		wire [C_M_AXI_DATA_DATA_WIDTH-1 : 0] rx_data;
		wire rx_data_valid;

		// Instruction Fetch FIFO
		wire        ifb_empty;
		wire        ifb_full;
		wire [7:0]  ifb_level = 0;
		wire [127:0]ifb_data; //instruction

		// Input Data Fetch FIFO
		wire [3:0]  idb_empty;
		wire [3:0]  idb_full;
		wire [7:0]  idb_level [3:0] = {0,0,0,0};	

		wire 		odb_empty;
		wire 		odb_full;

		// Control
		wire        csr_sel_ifb;
		wire [1:0]  csr_sel_idb;

		wire        csr_ifb_r_en;
		wire [3:0]  csr_idb_r_en;

		wire        ext_busy; // from csr auto reset to 1
		wire [1:0]  core_i_data_thread_id [3:0];


		// Selected Input FIFO full signal
		reg sel_i_fifo_full;
		

        // Core busy signals
        wire [3:0] core_busy_bus;
        wire [3:0] tile_busy_bus;
        wire [5:0] inst_status_bus [3:0];


// Instantiation of Axi Bus Interface S_CTRL_AXI
	DTCorev2_7_S_CTRL_AXI # ( 
		.C_S_AXI_DATA_WIDTH(C_S_CTRL_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH(C_S_CTRL_AXI_ADDR_WIDTH)
	) DTCorev2_7_S_CTRL_AXI_inst (

		.i_core_idle(core_idle),
		.i_any_tilewb_full(any_tilewb_full),
		.i_error_tile_wb_conflict(any_error_tile_wb_conflict),
		.i_error_op(any_error_op),

		.i_agu_slot_ready(agu_slot_ready),
		.i_agu_slot_busy(agu_slot_busy),
		.i_core_busy(core_busy_bus),
		.i_tile_busy(tile_busy_bus),

		.i_inst_status(inst_status_bus),

		.o_dtc_en(dtc_en),
		.o_soft_rst(soft_rst),
		.o_irq_en(irq_en),
		.o_ext_busy(ext_busy),
		.o_irq(o_irq),

		.o_issue_type(issue_type),
		// from Data/IFB FIFO
		.i_ifb_empty(ifb_empty),
		.i_ifb_full(ifb_full),
		.i_ifb_level(ifb_level),
		.i_ifb_data(ifb_data), //instruction
		.i_idb_empty(idb_empty),
		.i_idb_full(idb_full),
		.i_idb_level(idb_level),
		.i_odb_empty(odb_empty),
		.i_odb_full(odb_system_full),
		// To Data/IFB FIFO
		.o_ifb_r_en(csr_ifb_r_en),
		.o_idb_r_en(csr_idb_r_en),

		// from Master
		.i_m_txn_done(m_txn_done),
		.i_m_rxn_done(m_rxn_done),
		.i_m_error(m_error),
		.i_last_bresp(m_last_bresp),
		.i_last_rresp(m_last_rresp),
		//To Master
		.o_m_w_start(m_w_start),
		.o_m_r_start(m_r_start),
		.o_m_w_addr_lo(m_w_addr_lo),
		.o_m_w_addr_hi(m_w_addr_hi),
		.o_m_w_len(m_w_len),
		.o_m_r_addr_lo(m_r_addr_lo),
		.o_m_r_addr_hi(m_r_addr_hi),
		.o_m_r_len(m_r_len),
		// Control Master throttle/ Target
		.o_throttle_inst(),     
		.o_throttle_idb(),      
		.o_dst_sel_inst(csr_sel_ifb),      
		.o_dst_data_port(csr_sel_idb),

		.o_thread_id(core_i_data_thread_id),

		.S_AXI_ACLK(s_ctrl_axi_aclk),
		.S_AXI_ARESETN(s_ctrl_axi_aresetn),
		.S_AXI_AWADDR(s_ctrl_axi_awaddr),
		.S_AXI_AWPROT(s_ctrl_axi_awprot),
		.S_AXI_AWVALID(s_ctrl_axi_awvalid),
		.S_AXI_AWREADY(s_ctrl_axi_awready),
		.S_AXI_WDATA(s_ctrl_axi_wdata),
		.S_AXI_WSTRB(s_ctrl_axi_wstrb),
		.S_AXI_WVALID(s_ctrl_axi_wvalid),
		.S_AXI_WREADY(s_ctrl_axi_wready),
		.S_AXI_BRESP(s_ctrl_axi_bresp),
		.S_AXI_BVALID(s_ctrl_axi_bvalid),
		.S_AXI_BREADY(s_ctrl_axi_bready),
		.S_AXI_ARADDR(s_ctrl_axi_araddr),
		.S_AXI_ARPROT(s_ctrl_axi_arprot),
		.S_AXI_ARVALID(s_ctrl_axi_arvalid),
		.S_AXI_ARREADY(s_ctrl_axi_arready),
		.S_AXI_RDATA(s_ctrl_axi_rdata),
		.S_AXI_RRESP(s_ctrl_axi_rresp),
		.S_AXI_RVALID(s_ctrl_axi_rvalid),
		.S_AXI_RREADY(s_ctrl_axi_rready)
	);

// Instantiation of Axi Bus Interface M_AXI_DATA
	M_AXI_DATA_F_FSM # ( 
		.C_M_AXI_MAX_BURST_LEN(C_M_AXI_DATA_MAX_BURST_LEN),
		.C_M_AXI_ID_WIDTH(C_M_AXI_DATA_ID_WIDTH),
		.C_M_AXI_ADDR_WIDTH(C_M_AXI_DATA_ADDR_WIDTH),
		.C_M_AXI_DATA_WIDTH(C_M_AXI_DATA_DATA_WIDTH)
	) DTC_M_AXI_DATA_F_FSM (

		.i_m_w_start(m_w_start),      	// to o_m_w_start
		.i_m_r_start(m_r_start),      	// from o_m_r_start

		.i_m_w_addr_lo(m_w_addr_lo),    // from o_m_w_addr_lo
		.i_m_w_addr_hi(m_w_addr_hi),    // from o_m_w_addr_hi
		.i_m_w_len(m_w_len),        	// from o_m_w_len (only low 8 bit)
		.i_m_r_addr_lo(m_r_addr_lo),    // from o_m_r_addr_lo
		.i_m_r_addr_hi(m_r_addr_hi),    // from o_m_r_addr_hi
		.i_m_r_len(m_r_len),        	// from o_m_r_len

		.o_m_txn_done(m_txn_done),      // to i_m_txn_done
		.o_m_rxn_done(m_rxn_done),      // to i_m_rxn_done
		.o_m_error(m_error),        	// to i_m_error
		.o_m_last_bresp(m_last_bresp),  // to i_last_bresp
		.o_m_last_rresp(m_last_rresp),  // to i_last_rresp

		.i_tx_data(tx_data),
		.i_tx_data_valid(tx_data_valid),
		.o_tx_fifo_ren(tx_fifo_rd_en),  // to r_en of TX FIFO

		.o_rx_data(rx_data),
		.o_rx_data_valid(rx_data_valid),
		.o_rx_fifo_wen(),				// to w_en of RX FIFO
		.i_rx_fifo_full(sel_i_fifo_full), // from full of sel RX FIFO

		.M_AXI_ACLK(m_axi_data_aclk),
		.M_AXI_ARESETN(m_axi_data_aresetn),
		.M_AXI_AWID(m_axi_data_awid),
		.M_AXI_AWADDR(m_axi_data_awaddr),
		.M_AXI_AWLEN(m_axi_data_awlen),
		.M_AXI_AWSIZE(m_axi_data_awsize),
		.M_AXI_AWBURST(m_axi_data_awburst),
		.M_AXI_AWLOCK(m_axi_data_awlock),
		.M_AXI_AWCACHE(m_axi_data_awcache),
		.M_AXI_AWPROT(m_axi_data_awprot),
		.M_AXI_AWQOS(m_axi_data_awqos),
		.M_AXI_AWVALID(m_axi_data_awvalid),
		.M_AXI_AWREADY(m_axi_data_awready),
		.M_AXI_WDATA(m_axi_data_wdata),
		.M_AXI_WSTRB(m_axi_data_wstrb),
		.M_AXI_WLAST(m_axi_data_wlast),
		.M_AXI_WVALID(m_axi_data_wvalid),
		.M_AXI_WREADY(m_axi_data_wready),
		.M_AXI_BID(m_axi_data_bid),
		.M_AXI_BRESP(m_axi_data_bresp),
		.M_AXI_BVALID(m_axi_data_bvalid),
		.M_AXI_BREADY(m_axi_data_bready),
		.M_AXI_ARID(m_axi_data_arid),
		.M_AXI_ARADDR(m_axi_data_araddr),
		.M_AXI_ARLEN(m_axi_data_arlen),
		.M_AXI_ARSIZE(m_axi_data_arsize),
		.M_AXI_ARBURST(m_axi_data_arburst),
		.M_AXI_ARLOCK(m_axi_data_arlock),
		.M_AXI_ARCACHE(m_axi_data_arcache),
		.M_AXI_ARPROT(m_axi_data_arprot),
		.M_AXI_ARQOS(m_axi_data_arqos),
		.M_AXI_ARVALID(m_axi_data_arvalid),
		.M_AXI_ARREADY(m_axi_data_arready),
		.M_AXI_RID(m_axi_data_rid),
		.M_AXI_RDATA(m_axi_data_rdata),
		.M_AXI_RRESP(m_axi_data_rresp),
		.M_AXI_RLAST(m_axi_data_rlast),
		.M_AXI_RVALID(m_axi_data_rvalid),
		.M_AXI_RREADY(m_axi_data_rready)
	);


	wire [127:0] core_inst;
	wire [3:0] core_inst_valid;

	wire [127:0] core_i_data [3:0];

	wire [3:0] read_idb_data;

	// fetch instruction
	wire [3:0] fetch_bus;
	wire [3:0] r_ifb;
	assign r_ifb = {4{csr_ifb_r_en}}& fetch_bus;
	assign ifb_data = core_inst;

	// only use one port other reserver for scale-out
	wire [127:0] core_o_data [3:0];
	wire [3:0] 	 core_o_data_valid;

	always @(*) begin
		case({csr_sel_ifb,csr_sel_idb})
			3'b100: sel_i_fifo_full = ifb_full;
			3'b000: sel_i_fifo_full = idb_full[0];
			3'b001: sel_i_fifo_full = idb_full[1];
			3'b010: sel_i_fifo_full = idb_full[2];
			3'b011: sel_i_fifo_full = idb_full[3];
			default: sel_i_fifo_full = 1'b0;
		endcase
	end

	// Instruction Fetch Buffer
	IFB #(
		.DWIDTH(128)
	) IFB_inst(
		.clk(clk),
		.rst_n(rst_n),
		.ifb_wr_en(csr_sel_ifb),
		.ifb_rd_en(r_ifb),
		.ifb_din(rx_data),
		.ifb_din_valid(rx_data_valid),
		.ifb_dout(core_inst),
		.ifb_empty(ifb_empty),
		.ifb_full(ifb_full),
		.ifb_dout_valid(core_inst_valid)
	);

	// Input Data Buffer
	IDB #(
		.DWIDTH(128)
	) IDB_inst(
		.clk(clk),
		.rst_n(rst_n),
		.idb_wr_sel_en_n(csr_sel_ifb),
		.idb_wr_sel(csr_sel_idb),
		.idb_rd_en(csr_idb_r_en),
		.core_req(read_idb_data),
		.idb_din(rx_data),
		.idb_din_valid(rx_data_valid),
		.idb_dout(core_i_data),
		.idb_empty(idb_empty),
		.idb_full(idb_full),
		.idb_dout_valid()
	);

	// DTCore
	DTCore #(
		.CORE_ID(0)
	)DTCore_inst(
		.clk(clk),
		.rst_n(rst_n),

		.i_inst(core_inst),
		.i_inst_valid(core_inst_valid),

		.i_core_data(core_i_data),
		.i_core_data_thread_id(core_i_data_thread_id),

		.o_core_data(core_o_data),
		.o_core_data_thread_id(),

		.o_core_data_last(),
		.o_core_data_valid(core_o_data_valid),

		.o_tilewb_fifo_full(tilewb_fifo_full),
		.o_error_tile_wb_conflict(error_tile_wb_conflict),
		.o_error_op(error_op),

		.o_agu_ready(),
		.o_agu_busy(),
		.o_agu_slot_ready(agu_slot_ready),
		.o_agu_slot_busy(agu_slot_busy),

		.i_ext_busy(ext_busy),
		.o_core_busy_bus(core_busy_bus),
		.o_tile_busy_bus(tile_busy_bus),
		.o_status_bus(inst_status_bus),

		.o_read_data(read_idb_data),

		.o_fetch(fetch_bus) 

	);


	// 定義連接 Skid Buffer 與 ODB 之間的中介訊號
    wire [127:0] skid_to_odb_data;
    wire         skid_to_odb_valid;
    wire         skid_s_ready;       // Skid Buffer 給 Core 的 Ready 訊號
    wire         odb_system_full;    // 真正的系統滿訊號 (考慮到 Skid Buffer)
    assign       odb_system_full = odb_full; // Connect FIFO status to system signal


	pipeline_register_slice #(
        .DWIDTH(128)
    ) ODB_Pipeline_Cut (
        .clk(clk),
        .rst_n(rst_n),

        // Slave Interface (來自 DTCore)
        .s_valid (core_o_data_valid[0]), 
        .s_ready (skid_s_ready),         // 這訊號現在是純 Register 驅動，Timing 極佳
        .s_data  (core_o_data[0]),       

        // Master Interface (輸出給 ODB FIFO)
        .m_valid (skid_to_odb_valid),    // 這訊號現在是純 Register 輸出
        .m_ready (!odb_full),            
        .m_data  (skid_to_odb_data)      // 這訊號現在是純 Register 輸出
    );

	ODB #(
        .DWIDTH(128)
    ) ODB_inst(
        .clk(clk),
        .rst_n(rst_n),
        
        // 寫入端 (來自 Skid Buffer)
        .wr_en(skid_to_odb_valid),
        .din(skid_to_odb_data),
        .full(odb_full),              // 這裡的 full 只回饋給 Skid Buffer
        
        // 讀取端 (來自 AXI TX 模組)
        .rd_en(tx_fifo_rd_en),
        .dout(tx_data),
        .empty(odb_empty),
        .data_valid(tx_data_valid)
    );

endmodule
