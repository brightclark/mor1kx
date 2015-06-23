/* ****************************************************************************
  This Source Code Form is subject to the terms of the
  Open Hardware Description License, v. 1.0. If a copy
  of the OHDL was not distributed with this file, You
  can obtain one at http://juliusbaxter.net/ohdl/ohdl.txt

  Description: MAROCCHINO pipeline CPU module.
               Derived from mor1kx_cpu_cappuccino.

  Copyright (C) 2012 Julius Baxter <juliusbaxter@gmail.com>
  Copyright (C) 2015 Andrey Bacherov <avbacherov@opencores.org>

***************************************************************************** */

`include "mor1kx-defines.v"

module mor1kx_cpu_marocchino
#(
  parameter OPTION_OPERAND_WIDTH = 32,
  // data cache
  parameter FEATURE_DATACACHE         = "NONE",
  parameter OPTION_DCACHE_BLOCK_WIDTH = 5,
  parameter OPTION_DCACHE_SET_WIDTH   = 9,
  parameter OPTION_DCACHE_WAYS        = 2,
  parameter OPTION_DCACHE_LIMIT_WIDTH = 32,
  parameter OPTION_DCACHE_SNOOP       = "NONE",
  // data mmu
  parameter FEATURE_DMMU               = "NONE",
  parameter FEATURE_DMMU_HW_TLB_RELOAD = "NONE",
  parameter OPTION_DMMU_SET_WIDTH      = 6,
  parameter OPTION_DMMU_WAYS           = 1,
  // instruction cache
  parameter FEATURE_INSTRUCTIONCACHE   = "NONE",
  parameter OPTION_ICACHE_BLOCK_WIDTH  = 5,
  parameter OPTION_ICACHE_SET_WIDTH    = 9,
  parameter OPTION_ICACHE_WAYS         = 2,
  parameter OPTION_ICACHE_LIMIT_WIDTH  = 32,
  // instruction mmu
  parameter FEATURE_IMMU               = "NONE",
  parameter FEATURE_IMMU_HW_TLB_RELOAD = "NONE",
  parameter OPTION_IMMU_SET_WIDTH      = 6,
  parameter OPTION_IMMU_WAYS           = 1,

  parameter FEATURE_TIMER        = "ENABLED",
  parameter FEATURE_DEBUGUNIT    = "NONE",
  parameter FEATURE_PERFCOUNTERS = "NONE",

  parameter FEATURE_SYSCALL = "ENABLED",
  parameter FEATURE_TRAP    = "ENABLED",
  parameter FEATURE_RANGE   = "ENABLED",

  parameter FEATURE_PIC          = "ENABLED",
  parameter OPTION_PIC_TRIGGER   = "LEVEL",
  parameter OPTION_PIC_NMI_WIDTH = 0,

  parameter FEATURE_DSX        = "NONE",
  parameter FEATURE_OVERFLOW   = "NONE",
  parameter FEATURE_CARRY_FLAG = "ENABLED",

  parameter FEATURE_FASTCONTEXTS     = "NONE",
  parameter OPTION_RF_NUM_SHADOW_GPR = 0,
  parameter OPTION_RF_CLEAR_ON_INIT  = 0,
  parameter OPTION_RF_ADDR_WIDTH     = 5,

  parameter OPTION_RESET_PC = {{(OPTION_OPERAND_WIDTH-13){1'b0}},
                              `OR1K_RESET_VECTOR,8'd0},

  parameter FEATURE_EXT   = "NONE",
  parameter FEATURE_MSYNC = "ENABLED",
  parameter FEATURE_PSYNC = "NONE",
  parameter FEATURE_CSYNC = "NONE",

  parameter FEATURE_ATOMIC = "ENABLED",

  parameter FEATURE_FPU    = "NONE", // ENABLED|NONE: pipeline marocchino

  parameter FEATURE_STORE_BUFFER            = "ENABLED",
  parameter OPTION_STORE_BUFFER_DEPTH_WIDTH = 8,

  parameter FEATURE_MULTICORE      = "NONE",

  parameter FEATURE_TRACEPORT_EXEC = "NONE"
)
(
  input                             clk,
  input                             rst,

  // Instruction bus
  input                             ibus_err_i,
  input                             ibus_ack_i,
  input      [`OR1K_INSN_WIDTH-1:0] ibus_dat_i,
  output [OPTION_OPERAND_WIDTH-1:0] ibus_adr_o,
  output                            ibus_req_o,
  output                            ibus_burst_o,

  // Data bus
  input                             dbus_err_i,
  input                             dbus_ack_i,
  input  [OPTION_OPERAND_WIDTH-1:0] dbus_dat_i,
  output [OPTION_OPERAND_WIDTH-1:0] dbus_adr_o,
  output [OPTION_OPERAND_WIDTH-1:0] dbus_dat_o,
  output                            dbus_req_o,
  output                      [3:0] dbus_bsel_o,
  output                            dbus_we_o,
  output                            dbus_burst_o,

  // Interrupts
  input                      [31:0] irq_i,

  // Debug interface
  input                      [15:0] du_addr_i,
  input                             du_stb_i,
  input  [OPTION_OPERAND_WIDTH-1:0] du_dat_i,
  input                             du_we_i,
  output [OPTION_OPERAND_WIDTH-1:0] du_dat_o,
  output                            du_ack_o,
  // Stall control from debug interface
  input                             du_stall_i,
  output                            du_stall_o,

  output reg                        traceport_exec_valid_o,
  output reg [31:0]                 traceport_exec_pc_o,
  output reg [`OR1K_INSN_WIDTH-1:0] traceport_exec_insn_o,
  output [OPTION_OPERAND_WIDTH-1:0] traceport_exec_wbdata_o,
  output [OPTION_RF_ADDR_WIDTH-1:0] traceport_exec_wbreg_o,
  output                            traceport_exec_wben_o,

  // SPR accesses to external units (cache, mmu, etc.)
  output [15:0]                     spr_bus_addr_o,
  output                            spr_bus_we_o,
  output                            spr_bus_stb_o,
  output [OPTION_OPERAND_WIDTH-1:0] spr_bus_dat_o,
  input  [OPTION_OPERAND_WIDTH-1:0] spr_bus_dat_mac_i,
  input                             spr_bus_ack_mac_i,
  input  [OPTION_OPERAND_WIDTH-1:0] spr_bus_dat_pmu_i,
  input                             spr_bus_ack_pmu_i,
  input  [OPTION_OPERAND_WIDTH-1:0] spr_bus_dat_pcu_i,
  input                             spr_bus_ack_pcu_i,
  input  [OPTION_OPERAND_WIDTH-1:0] spr_bus_dat_fpu_i,
  input                             spr_bus_ack_fpu_i,
  output                     [15:0] spr_sr_o,

  input  [OPTION_OPERAND_WIDTH-1:0] multicore_coreid_i,
  input  [OPTION_OPERAND_WIDTH-1:0] multicore_numcores_i,

  input                      [31:0] snoop_adr_i,
  input                             snoop_en_i
);

  wire [`OR1K_INSN_WIDTH-1:0]       dcod_insn;



  wire [OPTION_OPERAND_WIDTH-1:0]   pc_decode;
  wire [OPTION_OPERAND_WIDTH-1:0]   pc_exec;
  wire [OPTION_OPERAND_WIDTH-1:0]   pc_wb;
  wire [OPTION_OPERAND_WIDTH-1:0]   ctrl_epcr;



  wire lsu_atomic_flag_set;
  wire lsu_atomic_flag_clear;
  wire wb_atomic_flag_set;
  wire wb_atomic_flag_clear;

  wire exec_flag_set;
  wire exec_flag_clear;
  wire wb_flag_set;
  wire wb_flag_clear;

  wire exec_carry_set;
  wire exec_carry_clear;
  wire wb_carry_set;
  wire wb_carry_clear;

  wire exec_overflow_set;
  wire exec_overflow_clear;
  wire wb_overflow_set;
  wire wb_overflow_clear;

  wire ctrl_flag;
  wire ctrl_carry;


  wire [OPTION_OPERAND_WIDTH-1:0] alu_nl_result;
  wire [OPTION_OPERAND_WIDTH-1:0] lsu_result;
  wire [OPTION_OPERAND_WIDTH-1:0] mfspr_dat;
  wire [OPTION_OPERAND_WIDTH-1:0] wb_result;


  wire [`OR1K_FPCSR_WIDTH-1:0] exec_fpcsr;
  wire                         exec_fpcsr_set;
  wire [`OR1K_FPCSR_WIDTH-1:0] wb_fpcsr;
  wire                         wb_fpcsr_set;


  wire                 exec_op_mfspr;
  wire                 exec_op_mtspr;
  wire                 ctrl_mfspr_ack;
  wire                 ctrl_mtspr_ack;


  wire                 exec_valid;
  wire                 lsu_valid;


  wire [OPTION_OPERAND_WIDTH-1:0] dcod_rfb;
  wire [OPTION_OPERAND_WIDTH-1:0] exec_rfa;
  wire [OPTION_OPERAND_WIDTH-1:0] exec_rfb;


  wire [OPTION_RF_ADDR_WIDTH-1:0] exec_rfd_adr;
  wire                            exec_rf_wb;
  wire [OPTION_RF_ADDR_WIDTH-1:0] wb_rfd_adr;
  wire                            wb_rf_wb;


  wire                 dcod_bubble;
  wire                 exec_bubble;


  wire                 exec_op_branch;
  wire                 wb_delay_slot;


  wire [`OR1K_FPCSR_RM_SIZE-1:0] ctrl_fpu_round_mode;

  // branching
  wire                            dcod_op_bf;
  wire                            dcod_op_bnf;
  wire                            dcod_op_brcond;
  wire                            dcod_branch;
  wire [9:0]                      dcod_immjbr_upper;
  wire [OPTION_OPERAND_WIDTH-1:0] dcod_branch_target;
  wire [OPTION_OPERAND_WIDTH-1:0] exec_jal_result;
  wire [OPTION_OPERAND_WIDTH-1:0] exec_mispredict_target;
  wire                            branch_mispredict;
  wire                            predicted_flag;
  wire                            exec_predicted_flag;


  wire [OPTION_RF_ADDR_WIDTH-1:0] dcod_rfa_adr;
  wire [OPTION_RF_ADDR_WIDTH-1:0] dcod_rfb_adr;
  wire [OPTION_OPERAND_WIDTH-1:0] exec_immediate;
  wire                            exec_immediate_sel;


  wire [OPTION_OPERAND_WIDTH-1:0] exec_lsu_adr;
  wire                            exec_op_lsu_load;
  wire                            exec_op_lsu_store;
  wire                            exec_op_lsu_atomic;
  wire                      [1:0] exec_lsu_length;
  wire                            exec_lsu_zext;
  wire [OPTION_OPERAND_WIDTH-1:0] lsu_adr;

  wire                            exec_op_msync;
  wire                            msync_done;

  wire                            exec_op_alu;
  wire  [`OR1K_ALU_OPC_WIDTH-1:0] exec_opc_alu;
  wire  [`OR1K_ALU_OPC_WIDTH-1:0] exec_opc_alu_secondary;

  wire                            exec_op_add;
  wire                            exec_adder_do_sub;
  wire                            exec_adder_do_carry;

  wire                            exec_op_jal;
  wire                            exec_op_brcond;

  wire                            exec_op_div;
  wire                            exec_op_div_signed;
  wire                            exec_op_div_unsigned;

  wire                            exec_op_mul;

  wire                            exec_op_ffl1;
  wire                            exec_op_movhi;
  wire                            exec_op_setflag;
  wire                            exec_op_shift;

  wire    [`OR1K_FPUOP_WIDTH-1:0] exec_op_fpu;


  wire [OPTION_OPERAND_WIDTH-1:0] store_buffer_epcr;
  wire                            store_buffer_err;


  // SPR access buses (Unit -> CTRL part)
  //   GPR
  wire                            spr_gpr_ack;
  wire [OPTION_OPERAND_WIDTH-1:0] spr_gpr_dat;
  //   Data MMU
  wire [OPTION_OPERAND_WIDTH-1:0] spr_bus_dat_dmmu;
  wire                            spr_bus_ack_dmmu;
  //   Data Cache
  wire [OPTION_OPERAND_WIDTH-1:0] spr_bus_dat_dc;
  wire                            spr_bus_ack_dc;
  //   Insn MMU
  wire [OPTION_OPERAND_WIDTH-1:0] spr_bus_dat_immu;
  wire                            spr_bus_ack_immu;
  //   Insn Cache
  wire [OPTION_OPERAND_WIDTH-1:0] spr_bus_dat_ic;
  wire                            spr_bus_ack_ic;


  // Debug Unit
  wire                            du_restart;
  wire [OPTION_OPERAND_WIDTH-1:0] du_restart_pc;


  // pipeline controls from CTRL to units
  wire padv_fetch;
  wire padv_decode;
  wire exec_new_input; // 1-clock delayed of padv-decode
  wire padv_wb;
  wire wb_new_result; // 1-clock delayed of padv-wb
  wire pipeline_flush;


  // Exceptions: reporting from FETCH to DECODE
  wire dcod_except_ibus_err;
  wire dcod_except_ipagefault;
  wire dcod_except_itlb_miss;
  // Exceptions: reported by LSU
  wire lsu_except_dbus;
  wire lsu_except_dpagefault;
  wire lsu_except_dtlb_miss;
  wire lsu_except_align;
  wire lsu_excepts;
  // Exceptions: forwarding from DECODE/EXECUTE to EXECUTE/CTRL
  wire exec_except_ibus_err;
  wire exec_except_ipagefault;
  wire exec_except_itlb_miss;
  wire exec_except_ibus_align;
  wire exec_except_illegal;
  wire exec_except_syscall;
  wire exec_except_trap;
  // Exceptions: latched by WB latches for processing in CONTROL-unit
  wire wb_except_ibus_err;
  wire wb_except_ipagefault;
  wire wb_except_itlb_miss;
  wire wb_except_ibus_align;
  wire wb_except_illegal;
  wire wb_except_syscall;
  wire wb_except_trap;
  wire wb_except_dbus;
  wire wb_except_dpagefault;
  wire wb_except_dtlb_miss;
  wire wb_except_align;
  // flag to enabel/disable exeption processing
  //  depending on various events in pipeline
  wire exec_excepts_en;
  wire wb_excepts_en;
  // Exeptions process:
  wire exec_op_rfe;
  wire wb_op_rfe;
  wire ctrl_doing_rfe;
  wire ctrl_branch_exception;
  wire [OPTION_OPERAND_WIDTH-1:0] ctrl_branch_except_pc;
  //   exeptions process: fetch->ctrl
  wire fetch_ecxeption_taken;


  // FETCH none latched outputs
  wire                            fetch_rf_adr_valid; // fetch->rf
  wire [OPTION_RF_ADDR_WIDTH-1:0] fetch_rfa_adr;      // fetch->rf
  wire [OPTION_RF_ADDR_WIDTH-1:0] fetch_rfb_adr;      // fetch->rf
  wire                            fetch_valid;


  mor1kx_fetch_cappuccino
  #(
    .OPTION_OPERAND_WIDTH(OPTION_OPERAND_WIDTH),
    .OPTION_RESET_PC(OPTION_RESET_PC),
    .FEATURE_INSTRUCTIONCACHE(FEATURE_INSTRUCTIONCACHE),
    .OPTION_ICACHE_BLOCK_WIDTH(OPTION_ICACHE_BLOCK_WIDTH),
    .OPTION_ICACHE_SET_WIDTH(OPTION_ICACHE_SET_WIDTH),
    .OPTION_ICACHE_WAYS(OPTION_ICACHE_WAYS),
    .OPTION_ICACHE_LIMIT_WIDTH(OPTION_ICACHE_LIMIT_WIDTH),
    .FEATURE_IMMU(FEATURE_IMMU),
    .FEATURE_IMMU_HW_TLB_RELOAD(FEATURE_IMMU_HW_TLB_RELOAD),
    .OPTION_IMMU_SET_WIDTH(OPTION_IMMU_SET_WIDTH),
    .OPTION_IMMU_WAYS(OPTION_IMMU_WAYS)
  )
  u_fetch_cappuccino
  (
    // clocks & resets
    .clk  (clk),
    .rst  (rst),
    // Outputs
    //   SPR BUS: FETCH -> CTRL
    .spr_bus_dat_ic_o                 (spr_bus_dat_ic), // FETCH
    .spr_bus_ack_ic_o                 (spr_bus_ack_ic), // FETCH
    .spr_bus_dat_immu_o               (spr_bus_dat_immu), // FETCH
    .spr_bus_ack_immu_o               (spr_bus_ack_immu), // FETCH
    //   To Instruction bus bridge
    .ibus_req_o                       (ibus_req_o), // FETCH
    .ibus_adr_o                       (ibus_adr_o), // FETCH
    .ibus_burst_o                     (ibus_burst_o), // FETCH
    //   To DECODE
    .pc_decode_o                      (pc_decode), // FETCH
    .decode_insn_o                    (dcod_insn), // FETCH
    //   To RF
    .fetch_rfa_adr_o                  (fetch_rfa_adr), // FETCH (not latched, to RF)
    .fetch_rfb_adr_o                  (fetch_rfb_adr), // FETCH (not latched, to RF)
    .fetch_rf_adr_valid_o             (fetch_rf_adr_valid), // FETCH (bus-access-done & padv-fetch)
    //   To CTRL
    .decode_except_ibus_err_o         (dcod_except_ibus_err), // FETCH
    .decode_except_itlb_miss_o        (dcod_except_itlb_miss), // FETCH
    .decode_except_ipagefault_o       (dcod_except_ipagefault), // FETCH
    .fetch_exception_taken_o          (fetch_ecxeption_taken), // FETCH
    .fetch_valid_o                    (fetch_valid), // FETCH
    // Inputs
    //   SPR BUS: FETCH <- CTRL
    .spr_bus_addr_i                   (spr_bus_addr_o[15:0]), // FETCH
    .spr_bus_we_i                     (spr_bus_we_o), // FETCH
    .spr_bus_stb_i                    (spr_bus_stb_o), // FETCH
    .spr_bus_dat_i                    (spr_bus_dat_o), // FETCH
    //   SPR SR:  FETCH <- CTRL
    .ic_enable                        (spr_sr_o[`OR1K_SPR_SR_ICE]), // FETCH
    .immu_enable_i                    (spr_sr_o[`OR1K_SPR_SR_IME]), // FETCH
    .supervisor_mode_i                (spr_sr_o[`OR1K_SPR_SR_SM]), // FETCH
    //   From Instruction bus bridge
    .ibus_err_i                       (ibus_err_i), // FETCH
    .ibus_ack_i                       (ibus_ack_i), // FETCH
    .ibus_dat_i                       (ibus_dat_i[`OR1K_INSN_WIDTH-1:0]), // FETCH
    //   From CTRL (pipeline controls)
    .padv_i                           (padv_fetch),            // FETCH
    .padv_ctrl_i                      (1'b0),  // FETCH (small hack to delay immu spr reads by one cycle)
    .pipeline_flush_i                 (pipeline_flush),        // FETCH
    .doing_rfe_i                      (ctrl_doing_rfe), // FETCH
    //
    .decode_branch_i                  (dcod_branch),  // FETCH
    .decode_branch_target_i           (dcod_branch_target),  // FETCH
    .ctrl_branch_exception_i          (ctrl_branch_exception),  // FETCH
    .ctrl_branch_except_pc_i          (ctrl_branch_except_pc),  // FETCH
    .du_restart_i                     (du_restart),  // FETCH
    .du_restart_pc_i                  (du_restart_pc),        // FETCH
    .decode_op_brcond_i               (dcod_op_brcond),     // FETCH
    .branch_mispredict_i              (branch_mispredict),    // FETCH
    .execute_mispredict_target_i      (exec_mispredict_target)  // FETCH
  );



  mor1kx_decode_marocchino
  #(
    .OPTION_OPERAND_WIDTH(OPTION_OPERAND_WIDTH),
    .OPTION_RESET_PC(OPTION_RESET_PC),
    .OPTION_RF_ADDR_WIDTH(OPTION_RF_ADDR_WIDTH),
    .FEATURE_SYSCALL(FEATURE_SYSCALL),
    .FEATURE_TRAP(FEATURE_TRAP),
    .FEATURE_RANGE(FEATURE_RANGE),
    .FEATURE_EXT(FEATURE_EXT),
    .FEATURE_ATOMIC(FEATURE_ATOMIC),
    .FEATURE_MSYNC(FEATURE_MSYNC),
    .FEATURE_PSYNC(FEATURE_PSYNC),
    .FEATURE_CSYNC(FEATURE_CSYNC),
    .FEATURE_FPU(FEATURE_FPU) // pipeline cappuccino: decode instance
  )
  u_decode_marocchino
  (
    // clocks & resets
    .clk (clk),
    .rst (rst),
    // pipeline control signal in
    .padv_decode_i                    (padv_decode), // DECODE & DECODE->EXE
    .pipeline_flush_i                 (pipeline_flush), // DECODE & DECODE->EXE
    // INSN
    .dcod_insn_i                      (dcod_insn), // DECODE & DECODE->EXE
    .fetch_valid_i                    (fetch_valid), // DECODE & DECODE->EXE
    // PC
    .pc_decode_i                      (pc_decode), // DECODE & DECODE->EXE
    .pc_exec_o                        (pc_exec), // DECODE & DECODE->EXE
    // IMM
    .exec_immediate_o                 (exec_immediate), // DECODE & DECODE->EXE
    .exec_immediate_sel_o             (exec_immediate_sel), // DECODE & DECODE->EXE
    // GPR addresses
    .dcod_rfa_adr_o                   (dcod_rfa_adr), // DECODE & DECODE->EXE (not latched, to RF)
    .dcod_rfb_adr_o                   (dcod_rfb_adr), // DECODE & DECODE->EXE (not latched, to RF)
    .exec_rfd_adr_o                   (exec_rfd_adr), // DECODE & DECODE->EXE
    .exec_rf_wb_o                     (exec_rf_wb), // DECODE & DECODE->EXE
    // flag & branches
    .dcod_op_bf_o                     (dcod_op_bf), // DECODE & DECODE->EXE (not latched, to BRANCH PREDICTION)
    .dcod_op_bnf_o                    (dcod_op_bnf), // DECODE & DECODE->EXE (not latched, to BRANCH PREDICTION)
    .dcod_immjbr_upper_o              (dcod_immjbr_upper), // DECODE & DECODE->EXE (not latched, to BRANCH PREDICTION)
    .dcod_op_brcond_o                 (dcod_op_brcond), // DECODE & DECODE->EXE (not latched, to FETCH)
    .exec_op_setflag_o                (exec_op_setflag), // DECODE & DECODE->EXE
    .exec_op_brcond_o                 (exec_op_brcond), // DECODE & DECODE->EXE
    .exec_op_branch_o                 (exec_op_branch), // DECODE & DECODE->EXE
    .exec_op_jal_o                    (exec_op_jal), // DECODE & DECODE->EXE
    .exec_jal_result_o                (exec_jal_result), // DECODE & DECODE->EXE
    .dcod_rfb_i                       (dcod_rfb), // DECODE & DECODE->EXE
    .exec_rfb_i                       (exec_rfb), // DECODE & DECODE->EXE
    .dcod_branch_o                    (dcod_branch), // DECODE & DECODE->EXE
    .dcod_branch_target_o             (dcod_branch_target), // DECODE & DECODE->EXE
    .predicted_flag_i                 (predicted_flag), // DECODE & DECODE->EXE
    .exec_predicted_flag_o            (exec_predicted_flag), // DECODE & DECODE->EXE
    .exec_mispredict_target_o         (exec_mispredict_target), // DECODE & DECODE->EXE
    // LSU related
    .exec_op_lsu_load_o               (exec_op_lsu_load), // DECODE & DECODE->EXE
    .exec_op_lsu_store_o              (exec_op_lsu_store), // DECODE & DECODE->EXE
    .exec_op_lsu_atomic_o             (exec_op_lsu_atomic), // DECODE & DECODE->EXE
    .exec_lsu_length_o                (exec_lsu_length), // DECODE & DECODE->EXE
    .exec_lsu_zext_o                  (exec_lsu_zext), // DECODE & DECODE->EXE
    // Sync operations
    .exec_op_msync_o                  (exec_op_msync), // DECODE & DECODE->EXE
    // ALU/FPU related
    .exec_op_alu_o                    (exec_op_alu), // DECODE & DECODE->EXE
    .exec_op_add_o                    (exec_op_add), // DECODE & DECODE->EXE
    .exec_adder_do_sub_o              (exec_adder_do_sub), // DECODE & DECODE->EXE
    .exec_adder_do_carry_o            (exec_adder_do_carry), // DECODE & DECODE->EXE
    .exec_op_mul_o                    (exec_op_mul), // DECODE & DECODE->EXE
    .exec_op_div_o                    (exec_op_div), // DECODE & DECODE->EXE
    .exec_op_div_signed_o             (exec_op_div_signed), // DECODE & DECODE->EXE
    .exec_op_div_unsigned_o           (exec_op_div_unsigned), // DECODE & DECODE->EXE
    .exec_op_shift_o                  (exec_op_shift), // DECODE & DECODE->EXE
    .exec_op_ffl1_o                   (exec_op_ffl1), // DECODE & DECODE->EXE
    .exec_op_movhi_o                  (exec_op_movhi), // DECODE & DECODE->EXE
    .exec_op_fpu_o                    (exec_op_fpu), // DECODE & DECODE->EXE
    // ALU related opc
    .exec_opc_alu_o                   (exec_opc_alu), // DECODE & DECODE->EXE
    .exec_opc_alu_secondary_o         (exec_opc_alu_secondary), // DECODE & DECODE->EXE
    // MTSPR / MFSPR
    .exec_op_mfspr_o                  (exec_op_mfspr), // DECODE & DECODE->EXE
    .exec_op_mtspr_o                  (exec_op_mtspr), // DECODE & DECODE->EXE
    // Hazards resolving
    .dcod_bubble_o                    (dcod_bubble), // DECODE & DECODE->EXE (not latched, to CTRL)
    .exec_bubble_o                    (exec_bubble), // DECODE & DECODE->EXE
    // Exception flags
    //   income FETCH exception flags
    .dcod_except_ibus_err_i           (dcod_except_ibus_err), // DECODE & DECODE->EXE
    .dcod_except_itlb_miss_i          (dcod_except_itlb_miss), // DECODE & DECODE->EXE
    .dcod_except_ipagefault_i         (dcod_except_ipagefault), // DECODE & DECODE->EXE
    //   outcome latched exception flags
    .exec_except_ibus_err_o           (exec_except_ibus_err), // DECODE & DECODE->EXE
    .exec_except_itlb_miss_o          (exec_except_itlb_miss), // DECODE & DECODE->EXE
    .exec_except_ipagefault_o         (exec_except_ipagefault), // DECODE & DECODE->EXE
    .exec_except_illegal_o            (exec_except_illegal), // DECODE & DECODE->EXE
    .exec_except_ibus_align_o         (exec_except_ibus_align), // DECODE & DECODE->EXE
    .exec_except_syscall_o            (exec_except_syscall), // DECODE & DECODE->EXE
    .exec_except_trap_o               (exec_except_trap), // DECODE & DECODE->EXE
    .exec_excepts_en_o                (exec_excepts_en), // DECODE & DECODE->EXE
    // RFE proc
    .exec_op_rfe_o                    (exec_op_rfe) // DECODE & DECODE->EXE
  );


  mor1kx_branch_prediction
  #(
     .OPTION_OPERAND_WIDTH(OPTION_OPERAND_WIDTH)
  )
  u_branch_prediction
  (
    // clocks & resets
    .clk (clk),
    .rst (rst),
    // Outputs
    .predicted_flag_o                 (predicted_flag), // BRANCH PREDICTION
    .branch_mispredict_o              (branch_mispredict), // BRANCH PREDICTION
    // Inputs
    .op_bf_i                          (dcod_op_bf), // BRANCH PREDICTION
    .op_bnf_i                         (dcod_op_bnf), // BRANCH PREDICTION
    .immjbr_upper_i                   (dcod_immjbr_upper), // BRANCH PREDICTION
    .prev_op_brcond_i                 (exec_op_brcond), // BRANCH PREDICTION
    .prev_predicted_flag_i            (exec_predicted_flag), // BRANCH PREDICTION
    .flag_i                           (ctrl_flag) // BRANCH PREDICTION
  );


  mor1kx_execute_marocchino
  #(
    .OPTION_OPERAND_WIDTH(OPTION_OPERAND_WIDTH),
    .OPTION_RF_ADDR_WIDTH(OPTION_RF_ADDR_WIDTH),
    .FEATURE_OVERFLOW(FEATURE_OVERFLOW),
    .FEATURE_CARRY_FLAG(FEATURE_CARRY_FLAG),
    .FEATURE_EXT(FEATURE_EXT),
    .FEATURE_FPU(FEATURE_FPU) // pipeline cappuccino: execute-alu instance
  )
  u_execute_marocchino
  (
    // clocks & resets
    .clk (clk),
    .rst (rst),

    // pipeline controls
    .padv_decode_i                    (padv_decode), // EXE
    .padv_wb_i                        (padv_wb), // EXE  (for FPU)
    .pipeline_flush_i                 (pipeline_flush), // EXE

    // input data
    .rfa_i                            (exec_rfa), // EXE
    .rfb_i                            (exec_rfb), // EXE
    .immediate_i                      (exec_immediate), // EXE
    .immediate_sel_i                  (exec_immediate_sel), // EXE

    // opcode for alu
    .op_alu_i                         (exec_op_alu), // EXE
    .opc_alu_i                        (exec_opc_alu), // EXE
    .opc_alu_secondary_i              (exec_opc_alu_secondary), // EXE

    // adder's inputs
    .op_add_i                         (exec_op_add), // EXE
    .adder_do_sub_i                   (exec_adder_do_sub), // EXE
    .adder_do_carry_i                 (exec_adder_do_carry), // EXE
    // adder's outputs
    .exec_lsu_adr_o                   (exec_lsu_adr), // EXE

    // multiplier inputs
    .op_mul_i                         (exec_op_mul), // EXE

    // division inputs
    .op_div_i                         (exec_op_div), // EXE
    .op_div_signed_i                  (exec_op_div_signed), // EXE
    .op_div_unsigned_i                (exec_op_div_unsigned), // EXE

    // shift, ffl1, movhi
    .op_shift_i                       (exec_op_shift), // EXE
    .op_ffl1_i                        (exec_op_ffl1), // EXE
    .op_movhi_i                       (exec_op_movhi), // EXE

    // EXE  result forming
    .op_jal_i                         (exec_op_jal), // EXE
    .exec_jal_result_i                (exec_jal_result), // EXE
    .alu_nl_result_o                  (alu_nl_result), // EXE  (not latched, for debug only)

    // FPU related
    .op_fpu_i                         (exec_op_fpu), // EXE
    .fpu_round_mode_i                 (ctrl_fpu_round_mode), // EXE
    .exec_fpcsr_o                     (exec_fpcsr), // EXE
    .exec_fpcsr_set_o                 (exec_fpcsr_set), // EXE

    // flag related inputs
    .op_setflag_i                     (exec_op_setflag), // EXE
    .flag_i                           (ctrl_flag), // EXE
    // flag related outputs
    .exec_flag_set_o                  (exec_flag_set), // EXE
    .exec_flag_clear_o                (exec_flag_clear), // EXE

    // carry related inputs
    .carry_i                          (ctrl_carry), // EXE
    // carry related outputs
    .exec_carry_set_o                 (exec_carry_set), // EXE
    .exec_carry_clear_o               (exec_carry_clear), // EXE

    // owerflow related outputs
    .exec_overflow_set_o              (exec_overflow_set), // EXE
    .exec_overflow_clear_o            (exec_overflow_clear), // EXE

    // MTSPR & MFSPR related inputs
    .op_mtspr_i                       (exec_op_mtspr), // EXE
    .op_mfspr_i                       (exec_op_mfspr), // EXE
    .ctrl_mfspr_ack_i                 (ctrl_mfspr_ack), // EXE
    .ctrl_mtspr_ack_i                 (ctrl_mtspr_ack), // EXE

    // MSYNC related controls
    .op_msync_i                       (exec_op_msync), // EXE
    .msync_done_i                     (msync_done),  // EXE

    // LSU related inputs
    .op_lsu_load_i                    (exec_op_lsu_load), // EXE
    .op_lsu_store_i                   (exec_op_lsu_store), // EXE
    .lsu_valid_i                      (lsu_valid), // EXE
    .lsu_excepts_i                    (lsu_excepts), // EXE

    // EXEC ready flag
    .exec_valid_o                     (exec_valid) // EXE
  );


  mor1kx_lsu_marocchino
  #(
    .FEATURE_DATACACHE(FEATURE_DATACACHE),
    .OPTION_OPERAND_WIDTH(OPTION_OPERAND_WIDTH),
    .OPTION_DCACHE_BLOCK_WIDTH(OPTION_DCACHE_BLOCK_WIDTH),
    .OPTION_DCACHE_SET_WIDTH(OPTION_DCACHE_SET_WIDTH),
    .OPTION_DCACHE_WAYS(OPTION_DCACHE_WAYS),
    .OPTION_DCACHE_LIMIT_WIDTH(OPTION_DCACHE_LIMIT_WIDTH),
    .OPTION_DCACHE_SNOOP(OPTION_DCACHE_SNOOP),
    .FEATURE_DMMU(FEATURE_DMMU),
    .FEATURE_DMMU_HW_TLB_RELOAD(FEATURE_DMMU_HW_TLB_RELOAD),
    .OPTION_DMMU_SET_WIDTH(OPTION_DMMU_SET_WIDTH),
    .OPTION_DMMU_WAYS(OPTION_DMMU_WAYS),
    .FEATURE_STORE_BUFFER(FEATURE_STORE_BUFFER),
    .OPTION_STORE_BUFFER_DEPTH_WIDTH(OPTION_STORE_BUFFER_DEPTH_WIDTH),
    .FEATURE_ATOMIC(FEATURE_ATOMIC)
  )
  u_lsu_marocchino
  (
    // clocks & resets
    .clk (clk),
    .rst (rst),
    // Pipeline controls
    .padv_decode_i                    (padv_decode), // LSU
    .exec_new_input_i                 (exec_new_input), // LSU
    .pipeline_flush_i                 (pipeline_flush), // LSU
    // configuration
    .dc_enable_i                      (spr_sr_o[`OR1K_SPR_SR_DCE]), // LSU
    .dmmu_enable_i                    (spr_sr_o[`OR1K_SPR_SR_DME]), // LSU
    .supervisor_mode_i                (spr_sr_o[`OR1K_SPR_SR_SM]), // LSU
    // inter-module interface
    .spr_bus_addr_i                   (spr_bus_addr_o[15:0]), // LSU
    .spr_bus_we_i                     (spr_bus_we_o), // LSU
    .spr_bus_stb_i                    (spr_bus_stb_o), // LSU
    .spr_bus_dat_i                    (spr_bus_dat_o), // LSU
    .spr_bus_dat_dc_o                 (spr_bus_dat_dc), // LSU
    .spr_bus_ack_dc_o                 (spr_bus_ack_dc), // LSU
    .spr_bus_dat_dmmu_o               (spr_bus_dat_dmmu), // LSU
    .spr_bus_ack_dmmu_o               (spr_bus_ack_dmmu), // LSU
    // DBUS bridge interface
    .dbus_err_i                       (dbus_err_i), // LSU
    .dbus_ack_i                       (dbus_ack_i), // LSU
    .dbus_dat_i                       (dbus_dat_i[OPTION_OPERAND_WIDTH-1:0]), // LSU
    .dbus_adr_o                       (dbus_adr_o), // LSU
    .dbus_req_o                       (dbus_req_o), // LSU
    .dbus_dat_o                       (dbus_dat_o), // LSU
    .dbus_bsel_o                      (dbus_bsel_o[3:0]), // LSU
    .dbus_we_o                        (dbus_we_o), // LSU
    .dbus_burst_o                     (dbus_burst_o), // LSU
    // Cache sync for multi-core environment
    .snoop_adr_i                      (snoop_adr_i[31:0]), // LSU
    .snoop_en_i                       (snoop_en_i), // LSU
    // Exceprions & errors
    .store_buffer_epcr_o              (store_buffer_epcr), // LSU
    .store_buffer_err_o               (store_buffer_err), // LSU
    .ctrl_epcr_i                      (ctrl_epcr), // LSU
    .lsu_except_dbus_o                (lsu_except_dbus), // LSU
    .lsu_except_align_o               (lsu_except_align), // LSU
    .lsu_except_dtlb_miss_o           (lsu_except_dtlb_miss), // LSU
    .lsu_except_dpagefault_o          (lsu_except_dpagefault), // LSU
    .lsu_excepts_o                    (lsu_excepts), // LSU
    // Input from execute stage (decode's latches)
    .exec_lsu_adr_i                   (exec_lsu_adr), // LSU (just adder's output)
    .exec_rfb_i                       (exec_rfb), // LSU
    .exec_op_lsu_load_i               (exec_op_lsu_load), // LSU
    .exec_op_lsu_store_i              (exec_op_lsu_store), // LSU
    .exec_op_lsu_atomic_i             (exec_op_lsu_atomic), // LSU
    .exec_op_msync_i                  (exec_op_msync), // LSU
    .exec_lsu_length_i                (exec_lsu_length), // LSU
    .exec_lsu_zext_i                  (exec_lsu_zext), // LSU
    // Outputs
    .lsu_result_o                     (lsu_result), // LSU
    .lsu_adr_o                        (lsu_adr), // LSU
    .atomic_flag_set_o                (lsu_atomic_flag_set), // LSU
    .atomic_flag_clear_o              (lsu_atomic_flag_clear), // LSU
    .msync_done_o                     (msync_done), // LSU
    .lsu_valid_o                      (lsu_valid) // LSU
  );


  mor1kx_wb_mux_marocchino
  #(
    .OPTION_OPERAND_WIDTH(OPTION_OPERAND_WIDTH),
    .OPTION_RF_ADDR_WIDTH(OPTION_RF_ADDR_WIDTH)
  )
  u_wb_mux_marocchino
  (
    // clock & reset
    .clk                          (clk),
    .rst                          (rst),

    // pipeline control signal in
    .padv_wb_i                    (padv_wb), // WB_MUX
    .pipeline_flush_i             (pipeline_flush), // WB_MUX

    // from ALU
    .alu_nl_result_i              (alu_nl_result), // WB_MUX

    // from LSU
    .exec_op_lsu_load_i           (exec_op_lsu_load), // WB_MUX
    .lsu_excepts_i                (lsu_excepts), // WB_MUX
    .lsu_result_i                 (lsu_result), // WB_MUX

    // MFSPR
    .exec_op_mfspr_i              (exec_op_mfspr), // WB_MUX
    .mfspr_dat_i                  (mfspr_dat), // WB_MUX

    // destination address & write request flag
    .exec_bubble_i                (exec_bubble), // WB_MUX
    .exec_rfd_adr_i               (exec_rfd_adr), // WB_MUX
    .exec_rf_wb_i                 (exec_rf_wb), // WB_MUX

    // PC
    .pc_exec_i                    (pc_exec), // WB_MUX

    // Insn in delay slot indicator (exception processing)
    .exec_op_branch_i             (exec_op_branch), // WB_MUX

    // set/clear flags
    .lsu_atomic_flag_set_i        (lsu_atomic_flag_set), // WB_MUX
    .lsu_atomic_flag_clear_i      (lsu_atomic_flag_clear), // WB_MUX
    .exec_flag_set_i              (exec_flag_set), // WB_MUX
    .exec_flag_clear_i            (exec_flag_clear), // WB_MUX
    .exec_carry_set_i             (exec_carry_set), // WB_MUX
    .exec_carry_clear_i           (exec_carry_clear), // WB_MUX
    .exec_overflow_set_i          (exec_overflow_set), // WB_MUX
    .exec_overflow_clear_i        (exec_overflow_clear), // WB_MUX

    // FPU related
    .exec_fpcsr_i                 (exec_fpcsr), // WB_MUX
    .exec_fpcsr_set_i             (exec_fpcsr_set), // WB_MUX

    // EXCEPTIONS
    //  input exceptions
    .exec_except_ibus_err_i       (exec_except_ibus_err), // WB_MUX
    .exec_except_ipagefault_i     (exec_except_ipagefault), // WB_MUX
    .exec_except_itlb_miss_i      (exec_except_itlb_miss), // WB_MUX
    .exec_except_ibus_align_i     (exec_except_ibus_align), // WB_MUX
    .exec_except_illegal_i        (exec_except_illegal), // WB_MUX
    .exec_except_syscall_i        (exec_except_syscall), // WB_MUX
    .exec_except_trap_i           (exec_except_trap), // WB_MUX
    .lsu_except_dbus_err_i        (lsu_except_dbus), // WB_MUX
    .lsu_except_dpagefault_i      (lsu_except_dpagefault), // WB_MUX
    .lsu_except_dtlb_miss_i       (lsu_except_dtlb_miss), // WB_MUX
    .lsu_except_dbus_align_i      (lsu_except_align), // WB_MUX
    .exec_excepts_en_i            (exec_excepts_en), // WB_MUX
    //  output exceptions
    .wb_except_ibus_err_o         (wb_except_ibus_err), // WB_MUX
    .wb_except_ipagefault_o       (wb_except_ipagefault), // WB_MUX
    .wb_except_itlb_miss_o        (wb_except_itlb_miss), // WB_MUX
    .wb_except_ibus_align_o       (wb_except_ibus_align), // WB_MUX
    .wb_except_illegal_o          (wb_except_illegal), // WB_MUX
    .wb_except_syscall_o          (wb_except_syscall), // WB_MUX
    .wb_except_trap_o             (wb_except_trap), // WB_MUX
    .wb_except_dbus_o             (wb_except_dbus), // WB_MUX
    .wb_except_dpagefault_o       (wb_except_dpagefault), // WB_MUX
    .wb_except_dtlb_miss_o        (wb_except_dtlb_miss), // WB_MUX
    .wb_except_align_o            (wb_except_align), // WB_MUX
    .wb_excepts_en_o              (wb_excepts_en), // WB_MUX

    // RFE processing
    .doing_rfe_i                  (ctrl_doing_rfe), // WB_MUX
    .exec_op_rfe_i                (exec_op_rfe), // WB_MUX
    .wb_op_rfe_o                  (wb_op_rfe), // WB_MUX

    // muxed output
    .pc_wb_o                      (pc_wb), // WB_MUX
    .wb_delay_slot_o              (wb_delay_slot), // WB_MUX
    .wb_atomic_flag_set_o         (wb_atomic_flag_set), // WB_MUX
    .wb_atomic_flag_clear_o       (wb_atomic_flag_clear), // WB_MUX
    .wb_flag_set_o                (wb_flag_set), // WB_MUX
    .wb_flag_clear_o              (wb_flag_clear), // WB_MUX
    .wb_carry_set_o               (wb_carry_set), // WB_MUX
    .wb_carry_clear_o             (wb_carry_clear), // WB_MUX
    .wb_overflow_set_o            (wb_overflow_set), // WB_MUX
    .wb_overflow_clear_o          (wb_overflow_clear), // WB_MUX
    .wb_fpcsr_o                   (wb_fpcsr), // WB_MUX
    .wb_fpcsr_set_o               (wb_fpcsr_set), // WB_MUX
    .wb_result_o                  (wb_result), // WB_MUX
    .wb_rfd_adr_o                 (wb_rfd_adr), // WB_MUX
    .wb_rf_wb_o                   (wb_rf_wb) // WB_MUX
  );



  mor1kx_rf_marocchino
  #(
    .FEATURE_FASTCONTEXTS(FEATURE_FASTCONTEXTS),
    .OPTION_RF_NUM_SHADOW_GPR(OPTION_RF_NUM_SHADOW_GPR),
    .OPTION_OPERAND_WIDTH(OPTION_OPERAND_WIDTH),
    .OPTION_RF_CLEAR_ON_INIT(OPTION_RF_CLEAR_ON_INIT),
    .OPTION_RF_ADDR_WIDTH(OPTION_RF_ADDR_WIDTH),
    .FEATURE_DEBUGUNIT(FEATURE_DEBUGUNIT)
  )
  u_rf_marocchino
  (
    // clocks & resets
    .clk (clk),
    .rst (rst),
    // pipeline control signals
    .padv_decode_i                    (padv_decode), // RF
    .exec_new_input_i                 (exec_new_input), // RF (1-clock delayed of padv-decode)
    .wb_new_result_i                  (wb_new_result), // RF (1-clock delayed of padv-wb)
    .pipeline_flush_i                 (pipeline_flush), // RF
    // SPR bus
    .spr_bus_addr_i                   (spr_bus_addr_o[15:0]), // RF
    .spr_bus_stb_i                    (spr_bus_stb_o), // RF
    .spr_bus_we_i                     (spr_bus_we_o), // RF
    .spr_bus_dat_i                    (spr_bus_dat_o), // RF
    .spr_gpr_ack_o                    (spr_gpr_ack), // RF
    .spr_gpr_dat_o                    (spr_gpr_dat), // RF
    // from FETCH
    .fetch_rf_adr_valid_i             (fetch_rf_adr_valid), // RF
    .fetch_rfa_adr_i                  (fetch_rfa_adr), // RF
    .fetch_rfb_adr_i                  (fetch_rfb_adr), // RF
    // from DECODE
    .dcod_rfa_adr_i                   (dcod_rfa_adr), // RF
    .dcod_rfb_adr_i                   (dcod_rfb_adr), // RF
    // from EXECUTE
    .exec_rf_wb_i                     (exec_rf_wb), // RF
    .exec_rfd_adr_i                   (exec_rfd_adr), // RF
    // from WB
    .wb_rf_wb_i                       (wb_rf_wb), // RF
    .wb_rfd_adr_i                     (wb_rfd_adr), // RF
    .wb_result_i                      (wb_result), // RF
    // Outputs
    .dcod_rfb_o                       (dcod_rfb), // RF
    .exec_rfa_o                       (exec_rfa), // RF
    .exec_rfb_o                       (exec_rfb) // RF
  );


`ifndef SYNTHESIS
// synthesis translate_off
/* Debug signals required for the debug monitor
   function [OPTION_OPERAND_WIDTH-1:0] get_gpr;
      // verilator public
      input [4:0]        gpr_num;
      begin
   // TODO: handle load ops
   if ((mor1kx_rf_marocchino.exec_rfd_adr_i == gpr_num) &
       mor1kx_rf_marocchino.exec_rf_wb_i)
     get_gpr = alu_nl_result;
   else if ((mor1kx_rf_marocchino.ctrl_rfd_adr_i == gpr_num) &
      mor1kx_rf_marocchino.ctrl_rf_wb_i)
     get_gpr = ctrl_alu_result;
   else if ((mor1kx_rf_marocchino.wb_rfd_adr_i == gpr_num) &
      mor1kx_rf_marocchino.wb_rf_wb_i)
     get_gpr = mor1kx_rf_marocchino.result_i;
   else
     get_gpr = mor1kx_rf_marocchino.rfa.mem[gpr_num];
      end
   endfunction //


   task set_gpr;
      // verilator public
      input [4:0] gpr_num;
      input [OPTION_OPERAND_WIDTH-1:0] gpr_value;
      begin
   mor1kx_rf_marocchino.rfa.mem[gpr_num] = gpr_value;
   mor1kx_rf_marocchino.rfb.mem[gpr_num] = gpr_value;
      end
   endtask */
// synthesis translate_on
`endif


  mor1kx_ctrl_marocchino
  #(
    .OPTION_OPERAND_WIDTH(OPTION_OPERAND_WIDTH),
    .OPTION_RESET_PC(OPTION_RESET_PC),
    .FEATURE_PIC(FEATURE_PIC),
    .FEATURE_TIMER(FEATURE_TIMER),
    .OPTION_PIC_TRIGGER(OPTION_PIC_TRIGGER),
    .OPTION_PIC_NMI_WIDTH(OPTION_PIC_NMI_WIDTH),
    .FEATURE_DATACACHE(FEATURE_DATACACHE),
    .OPTION_DCACHE_BLOCK_WIDTH(OPTION_DCACHE_BLOCK_WIDTH),
    .OPTION_DCACHE_SET_WIDTH(OPTION_DCACHE_SET_WIDTH),
    .OPTION_DCACHE_WAYS(OPTION_DCACHE_WAYS),
    .FEATURE_DMMU(FEATURE_DMMU),
    .OPTION_DMMU_SET_WIDTH(OPTION_DMMU_SET_WIDTH),
    .OPTION_DMMU_WAYS(OPTION_DMMU_WAYS),
    .FEATURE_INSTRUCTIONCACHE(FEATURE_INSTRUCTIONCACHE),
    .OPTION_ICACHE_BLOCK_WIDTH(OPTION_ICACHE_BLOCK_WIDTH),
    .OPTION_ICACHE_SET_WIDTH(OPTION_ICACHE_SET_WIDTH),
    .OPTION_ICACHE_WAYS(OPTION_ICACHE_WAYS),
    .FEATURE_IMMU(FEATURE_IMMU),
    .OPTION_IMMU_SET_WIDTH(OPTION_IMMU_SET_WIDTH),
    .OPTION_IMMU_WAYS(OPTION_IMMU_WAYS),
    .FEATURE_DEBUGUNIT(FEATURE_DEBUGUNIT),
    .FEATURE_PERFCOUNTERS(FEATURE_PERFCOUNTERS),
    .FEATURE_MAC("NONE"),
    .FEATURE_FPU(FEATURE_FPU), // pipeline MAROCCHINO: ctrl instance
    .FEATURE_MULTICORE(FEATURE_MULTICORE),
    .FEATURE_SYSCALL(FEATURE_SYSCALL),
    .FEATURE_TRAP(FEATURE_TRAP),
    .FEATURE_RANGE(FEATURE_RANGE),
    .FEATURE_DSX(FEATURE_DSX),
    .FEATURE_FASTCONTEXTS(FEATURE_FASTCONTEXTS),
    .OPTION_RF_NUM_SHADOW_GPR(OPTION_RF_NUM_SHADOW_GPR),
    .FEATURE_OVERFLOW(FEATURE_OVERFLOW),
    .FEATURE_CARRY_FLAG(FEATURE_CARRY_FLAG)
  )
  u_ctrl_marocchino
  (
    // clocks & resets
    .clk (clk),
    .rst (rst),
    // Outputs
    .ctrl_epcr_o                      (ctrl_epcr), // CTRL
    .mfspr_dat_o                      (mfspr_dat), // CTRL
    .ctrl_mfspr_ack_o                 (ctrl_mfspr_ack), // CTRL
    .ctrl_mtspr_ack_o                 (ctrl_mtspr_ack), // CTRL
    .ctrl_flag_o                      (ctrl_flag), // CTRL
    .ctrl_carry_o                     (ctrl_carry), // CTRL
    .ctrl_fpu_round_mode_o            (ctrl_fpu_round_mode), // CTRL
    .ctrl_branch_exception_o          (ctrl_branch_exception), // CTRL
    .ctrl_branch_except_pc_o          (ctrl_branch_except_pc), // CTRL
    .pipeline_flush_o                 (pipeline_flush), // CTRL
    .doing_rfe_o                      (ctrl_doing_rfe), // CTRL
    .padv_fetch_o                     (padv_fetch), // CTRL
    .padv_decode_o                    (padv_decode), // CTRL
    .exec_new_input_o                 (exec_new_input), // CTRL
    .padv_wb_o                        (padv_wb), // CTRL
    .wb_new_result_o                  (wb_new_result), // CTRL (1-clock delayed of padv-wb)
    .du_dat_o                         (du_dat_o), // CTRL
    .du_ack_o                         (du_ack_o), // CTRL
    .du_stall_o                       (du_stall_o), // CTRL
    .du_restart_pc_o                  (du_restart_pc), // CTRL
    .du_restart_o                     (du_restart), // CTRL
    .spr_bus_addr_o                   (spr_bus_addr_o[15:0]), // CTRL
    .spr_bus_we_o                     (spr_bus_we_o), // CTRL
    .spr_bus_stb_o                    (spr_bus_stb_o), // CTRL
    .spr_bus_dat_o                    (spr_bus_dat_o), // CTRL
    .spr_sr_o                         (spr_sr_o[15:0]), // CTRL
    // Inputs
    .lsu_adr_i                        (lsu_adr), // CTRL
    .exec_rfb_i                       (exec_rfb), // CTRL
    .wb_flag_set_i                    (wb_flag_set), // CTRL
    .wb_flag_clear_i                  (wb_flag_clear), // CTRL
    .wb_atomic_flag_set_i             (wb_atomic_flag_set), // CTRL
    .wb_atomic_flag_clear_i           (wb_atomic_flag_clear), // CTRL
    .wb_carry_set_i                   (wb_carry_set), // CTRL
    .wb_carry_clear_i                 (wb_carry_clear), // CTRL
    .wb_overflow_set_i                (wb_overflow_set), // CTRL
    .wb_overflow_clear_i              (wb_overflow_clear), // CTRL
    .pc_wb_i                          (pc_wb), // CTRL
    .alu_nl_result_i                  (alu_nl_result), // CTRL
    .exec_op_mfspr_i                  (exec_op_mfspr), // CTRL
    .exec_op_mtspr_i                  (exec_op_mtspr), // CTRL
    .wb_op_rfe_i                      (wb_op_rfe), // CTRL
    .dcod_branch_i                    (dcod_branch), // CTRL
    .dcod_branch_target_i             (dcod_branch_target), // CTRL
    .branch_mispredict_i              (branch_mispredict), // CTRL
    .exec_mispredict_target_i         (exec_mispredict_target), // CTRL
    .pc_exec_i                        (pc_exec), // CTRL
    .exec_op_branch_i                 (exec_op_branch), // CTRL
    .wb_delay_slot_i                  (wb_delay_slot), // CTRL
    .except_ibus_err_i                (wb_except_ibus_err), // CTRL
    .except_itlb_miss_i               (wb_except_itlb_miss), // CTRL
    .except_ipagefault_i              (wb_except_ipagefault), // CTRL
    .except_ibus_align_i              (wb_except_ibus_align), // CTRL
    .except_illegal_i                 (wb_except_illegal), // CTRL
    .except_syscall_i                 (wb_except_syscall), // CTRL
    .except_dbus_i                    (wb_except_dbus), // CTRL
    .except_dtlb_miss_i               (wb_except_dtlb_miss), // CTRL
    .except_dpagefault_i              (wb_except_dpagefault), // CTRL
    .except_trap_i                    (wb_except_trap), // CTRL
    .except_align_i                   (wb_except_align), // CTRL
    .wb_excepts_en_i                  (wb_excepts_en), // CTRL
    .fetch_valid_i                    (fetch_valid), // CTRL
    .exec_valid_i                     (exec_valid), // CTRL
    .fetch_exception_taken_i          (fetch_ecxeption_taken), // CTRL
    .dcod_bubble_i                    (dcod_bubble), // CTRL
    .exec_bubble_i                    (exec_bubble), // CTRL
    .irq_i                            (irq_i[31:0]), // CTRL
    .store_buffer_epcr_i              (store_buffer_epcr), // CTRL
    .store_buffer_err_i               (store_buffer_err), // CTRL
    .wb_fpcsr_i                       (wb_fpcsr), // CTRL
    .wb_fpcsr_set_i                   (wb_fpcsr_set), // CTRL
    .du_addr_i                        (du_addr_i[15:0]), // CTRL
    .du_stb_i                         (du_stb_i), // CTRL
    .du_dat_i                         (du_dat_i), // CTRL
    .du_we_i                          (du_we_i), // CTRL
    .du_stall_i                       (du_stall_i), // CTRL
    .spr_bus_dat_dc_i                 (spr_bus_dat_dc), // CTRL
    .spr_bus_ack_dc_i                 (spr_bus_ack_dc), // CTRL
    .spr_bus_dat_ic_i                 (spr_bus_dat_ic), // CTRL
    .spr_bus_ack_ic_i                 (spr_bus_ack_ic), // CTRL
    .spr_bus_dat_dmmu_i               (spr_bus_dat_dmmu), // CTRL
    .spr_bus_ack_dmmu_i               (spr_bus_ack_dmmu), // CTRL
    .spr_bus_dat_immu_i               (spr_bus_dat_immu), // CTRL
    .spr_bus_ack_immu_i               (spr_bus_ack_immu), // CTRL
    .spr_bus_dat_mac_i                (spr_bus_dat_mac_i), // CTRL
    .spr_bus_ack_mac_i                (spr_bus_ack_mac_i), // CTRL
    .spr_bus_dat_pmu_i                (spr_bus_dat_pmu_i), // CTRL
    .spr_bus_ack_pmu_i                (spr_bus_ack_pmu_i), // CTRL
    .spr_bus_dat_pcu_i                (spr_bus_dat_pcu_i), // CTRL
    .spr_bus_ack_pcu_i                (spr_bus_ack_pcu_i), // CTRL
    .spr_bus_dat_fpu_i                (spr_bus_dat_fpu_i), // CTRL
    .spr_bus_ack_fpu_i                (spr_bus_ack_fpu_i), // CTRL
    .spr_gpr_dat_i                    (spr_gpr_dat), // CTRL
    .spr_gpr_ack_i                    (spr_gpr_ack), // CTRL
    .multicore_coreid_i               (multicore_coreid_i), // CTRL
    .multicore_numcores_i             (multicore_numcores_i) // CTRL
  );

/*
   reg [`OR1K_INSN_WIDTH-1:0] traceport_stage_dcod_insn;
   reg [`OR1K_INSN_WIDTH-1:0] traceport_stage_exec_insn;

   reg            traceport_waitexec;

   always @(posedge clk) begin
      if (FEATURE_TRACEPORT_EXEC != "NONE") begin
   if (rst) begin
      traceport_waitexec <= 0;
   end else begin
      if (padv_decode) begin
         traceport_stage_dcod_insn <= dcod_insn;
      end

      if (padv_execute) begin
         traceport_stage_exec_insn <= traceport_stage_dcod_insn;
      end

      if (ctrl_new_input) begin
         traceport_exec_insn_o <= traceport_stage_exec_insn;
      end

      traceport_exec_pc_o <= pc_ctrl;
      if (!traceport_waitexec) begin
         if (ctrl_new_input & !ctrl_bubble) begin
      if (exec_valid) begin
         traceport_exec_valid_o <= 1'b1;
      end else begin
         traceport_exec_valid_o <= 1'b0;
         traceport_waitexec <= 1'b1;
      end
         end else begin
      traceport_exec_valid_o <= 1'b0;
         end
      end else begin
         if (exec_valid) begin
      traceport_exec_valid_o <= 1'b1;
      traceport_waitexec <= 1'b0;
         end else begin
      traceport_exec_valid_o <= 1'b0;
         end
      end // else: !if(!traceport_waitexec)
   end // else: !if(rst)
      end else begin // if (FEATURE_TRACEPORT_EXEC != "NONE")
   traceport_stage_dcod_insn <= {`OR1K_INSN_WIDTH{1'b0}};
   traceport_stage_exec_insn <= {`OR1K_INSN_WIDTH{1'b0}};
   traceport_exec_insn_o <= {`OR1K_INSN_WIDTH{1'b0}};
   traceport_exec_pc_o <= 32'h0;
   traceport_exec_valid_o <= 1'b0;
      end
   end

   generate
      if (FEATURE_TRACEPORT_EXEC != "NONE") begin
   assign traceport_exec_wbreg_o = wb_rfd_adr;
   assign traceport_exec_wben_o = wb_rf_wb;
   assign traceport_exec_wbdata_o = wb_result;
      end else begin
   assign traceport_exec_wbreg_o = {OPTION_RF_ADDR_WIDTH{1'b0}};
   assign traceport_exec_wben_o = 1'b0;
   assign traceport_exec_wbdata_o = {OPTION_OPERAND_WIDTH{1'b0}};
      end
   endgenerate
*/
endmodule // mor1kx_cpu_marocchino