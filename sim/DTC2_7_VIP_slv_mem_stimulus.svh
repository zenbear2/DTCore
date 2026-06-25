`ifndef DTC2_7_VIP_SLV_MEM_STIMULUS_SVH
`define DTC2_7_VIP_SLV_MEM_STIMULUS_SVH

// ============================================================================
// Slave Memory Model Utility Tasks
// Ensure that 'slave_agent' is already declared and instantiated in the parent
// module before calling these tasks.
// ============================================================================

task set_mem_default_value_fixed(input bit [127:0] fill_payload);
    slave_agent.mem_model.set_memory_fill_policy(XIL_AXI_MEMORY_FILL_FIXED);
    slave_agent.mem_model.set_default_memory_value(fill_payload);
endtask

task set_mem_default_value_rand();
    slave_agent.mem_model.set_memory_fill_policy(XIL_AXI_MEMORY_FILL_RANDOM);
endtask

task backdoor_mem_write(
    input xil_axi_ulong addr, 
    input bit [127:0]   wr_data,
    input bit [15:0]    wr_strb = 16'hFFFF
);
    slave_agent.mem_model.backdoor_memory_write(addr, wr_data, wr_strb);
endtask

task backdoor_mem_read(
    input  xil_axi_ulong mem_rd_addr,
    output bit [127:0]   mem_rd_data
);
    // backdoor_memory_read API returns the data value, we assign it to the output
    mem_rd_data = slave_agent.mem_model.backdoor_memory_read(mem_rd_addr);
endtask

task load_mem_file_backdoor(input string file_name, input xil_axi_ulong start_addr);
    integer fd;
    integer count = 0;
    string  line;
    bit [127:0] data_val;
    xil_axi_ulong current_addr;

    current_addr = start_addr;

    // 1. Open the file for reading
    fd = $fopen(file_name, "r");
    if (fd == 0) begin
        $display("[Error] Failed to open file: %s", file_name);
        return;
    end

    $display("[Slave VIP] Starting to load data from file: %s", file_name);

// 2. Read line by line until End of File (EOF)
    while (!$feof(fd)) begin
        // Get a single line from the file
        if ($fgets(line, fd)) begin
            // Skip empty lines or lines starting with "//" (comments)
            if (line.len() > 1 && line.substr(0, 1) != "//") begin
                // Parse the hexadecimal string into a 128-bit variable
                if ($sscanf(line, "%h", data_val)) begin
                    // 3. Call the existing backdoor write utility task
                    // Note: Ensure slave_agent is instantiated in the parent module [cite: 1, 2]
                    backdoor_mem_write(current_addr, data_val, 16'hFFFF);
                    
                    // 4. Increment address (128-bit data equals 16 Bytes)
                    current_addr = current_addr + 16;
                    count++;
                end
            end
        end
    end

    $fclose(fd);
    $display("[Slave VIP] Loading complete. Total entries: %0d. End Address: %08h", count, current_addr);
endtask

`endif