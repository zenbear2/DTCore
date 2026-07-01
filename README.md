# DTCore
 A Structured Sparsity GEMM Engine for FPGAs
 
### Add IP in Project Repository

Click Setting



![image](https://github.com/zenbear2/DTCore/blob/main/image/Click_Setting.png)

Click IP
![image](https://github.com/zenbear2/DTCore/blob/main/image/Click_IP.png)

Click Repository & Add DTCore/HW to IP Repository
![image](https://github.com/zenbear2/DTCore/blob/main/image/Add_IP_2_Repository.png)
### Create DTCore VIP Desgin

File location: `sim/DTC2_7VIP.tcl`

```other
source sim/DTC2_7VIP.tcl
```

Create HDL Wrapper

Add `sim/DTC2_7_VIP_tb_irq.sv` & `sim/DTC2_7_VIP_slv_mem_stimulus.svh`to simulation source

edit `sim/DTC2_7_VIP_tb_irq.sv`  [load memory file location](https://github.com/zenbear2/DTCore/blob/77efc642aa9e006d4c8c9ee8dac59668526d1570/sim/DTC2_7_VIP_tb_irq.sv#L105)

Run simulation

Add S_AXI & M_AXI to Wave Window
![image](https://github.com/zenbear2/DTCore/blob/main/image/add_S_AXI_and_M_AXI.png)
Add o_tile_busy to Wave Window
![image](https://github.com/zenbear2/DTCore/blob/main/image/o_tile_busy.png)
Set time to 2500 ns & Run
![image](https://github.com/zenbear2/DTCore/blob/main/image/set_time.png)
Click Zoom Fit
![image](https://github.com/zenbear2/DTCore/blob/main/image/waveform.png)
You will see the AXI data fransfer and Tensor Tile is working

### Create DTCore ZCU102 Block Desgin

File location: `Platform/DTCSys_ZCU102.tcl`

```other
source Platform/DTCSys_ZCU102.tcl
```
