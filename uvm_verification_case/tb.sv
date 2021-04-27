`timescale 1ns/1ps

`include "param_def.v"

interface chnl_intf(input clk, input rstn);
  logic [31:0] ch_data;
  logic        ch_valid;
  logic        ch_ready;
  clocking drv_ck @(posedge clk);
    default input #1ns output #1ns;
    output ch_data, ch_valid;
    input ch_ready;
  endclocking
  clocking mon_ck @(posedge clk);
    default input #1ns output #1ns;
    input ch_data, ch_valid, ch_ready;
  endclocking
endinterface

interface reg_intf(input clk, input rstn);
  logic [1:0]                 cmd;
  logic [`ADDR_WIDTH-1:0]     cmd_addr;
  logic [`CMD_DATA_WIDTH-1:0] cmd_data_s2m;
  logic [`CMD_DATA_WIDTH-1:0] cmd_data_m2s;
  clocking drv_ck @(posedge clk);
    default input #1ns output #1ns;
    output cmd, cmd_addr, cmd_data_m2s;
    input cmd_data_s2m;
  endclocking
  clocking mon_ck @(posedge clk);
    default input #1ns output #1ns;
    input cmd, cmd_addr, cmd_data_m2s, cmd_data_s2m;
  endclocking
endinterface

interface arb_intf(input clk, input rstn);
  logic [1:0] slv_prios[3];
  logic slv_reqs[3];
  logic a2s_acks[3];
  logic f2a_id_req;
  clocking mon_ck @(posedge clk);
    default input #1ns output #1ns;
    input slv_prios, slv_reqs, a2s_acks, f2a_id_req;
  endclocking
endinterface

interface fmt_intf(input clk, input rstn);
  logic        fmt_grant;
  logic [1:0]  fmt_chid;
  logic        fmt_req;
  logic [5:0]  fmt_length;
  logic [31:0] fmt_data;
  logic        fmt_start;
  logic        fmt_end;
  clocking drv_ck @(posedge clk);
    default input #1ns output #1ns;
    input fmt_chid, fmt_req, fmt_length, fmt_data, fmt_start;
    output fmt_grant;
  endclocking
  clocking mon_ck @(posedge clk);
    default input #1ns output #1ns;
    input fmt_grant, fmt_chid, fmt_req, fmt_length, fmt_data, fmt_start;
  endclocking
endinterface

interface mcdf_intf(output logic clk, output logic rstn);
  // USER TODO
  // To define those signals which do not exsit in
  // reg_if, chnl_if, arb_if or fmt_if
  logic chnl_en[3];

  clocking mon_ck @(posedge clk);
    default input #1ns output #1ns;
    input chnl_en;
  endclocking
    
  // clock generation
  initial begin 
    clk <= 0;
    forever begin
      #5 clk <= !clk;
    end
  end
  
  // reset trigger
  initial begin 
    #10 rstn <= 0;
    repeat(10) @(posedge clk);
    rstn <= 1;
  end
endinterface

module tb;
  logic         clk;
  logic         rstn;

  mcdf dut(
     .clk_i       (clk                )
    ,.rstn_i      (rstn               )
    ,.cmd_i       (reg_if.cmd         ) 
    ,.cmd_addr_i  (reg_if.cmd_addr    ) 
    ,.cmd_data_i  (reg_if.cmd_data_m2s)  
    ,.cmd_data_o  (reg_if.cmd_data_s2m)  
    ,.ch0_data_i  (chnl0_if.ch_data   )
    ,.ch0_vld_i   (chnl0_if.ch_valid  )
    ,.ch0_ready_o (chnl0_if.ch_ready  )
    ,.ch1_data_i  (chnl1_if.ch_data   )
    ,.ch1_vld_i   (chnl1_if.ch_valid  )
    ,.ch1_ready_o (chnl1_if.ch_ready  )
    ,.ch2_data_i  (chnl2_if.ch_data   )
    ,.ch2_vld_i   (chnl2_if.ch_valid  )
    ,.ch2_ready_o (chnl2_if.ch_ready  )
    ,.fmt_grant_i (fmt_if.fmt_grant   ) 
    ,.fmt_chid_o  (fmt_if.fmt_chid    ) 
    ,.fmt_req_o   (fmt_if.fmt_req     ) 
    ,.fmt_length_o(fmt_if.fmt_length  )    
    ,.fmt_data_o  (fmt_if.fmt_data    )  
    ,.fmt_start_o (fmt_if.fmt_start   )  
    ,.fmt_end_o   (fmt_if.fmt_end     )  
  );


  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import chnl_pkg::*;
  import reg_pkg::*;
  import arb_pkg::*;
  import fmt_pkg::*;
  import mcdf_pkg::*;

  reg_intf  reg_if(.*);
  chnl_intf chnl0_if(.*);
  chnl_intf chnl1_if(.*);
  chnl_intf chnl2_if(.*);
  arb_intf  arb_if(.*);
  fmt_intf  fmt_if(.*);
  mcdf_intf mcdf_if(.*);

  // mcdf interface monitoring MCDF ports and signals
  assign mcdf_if.chnl_en[0] = tb.dut.ctrl_regs_inst.slv0_en_o;
  assign mcdf_if.chnl_en[1] = tb.dut.ctrl_regs_inst.slv1_en_o;
  assign mcdf_if.chnl_en[2] = tb.dut.ctrl_regs_inst.slv2_en_o;

  // arbiter interface monitoring arbiter ports
  assign arb_if.slv_prios[0] = tb.dut.arbiter_inst.slv0_prio_i;
  assign arb_if.slv_prios[1] = tb.dut.arbiter_inst.slv1_prio_i;
  assign arb_if.slv_prios[2] = tb.dut.arbiter_inst.slv2_prio_i;
  assign arb_if.slv_reqs[0] = tb.dut.arbiter_inst.slv0_req_i;
  assign arb_if.slv_reqs[1] = tb.dut.arbiter_inst.slv1_req_i;
  assign arb_if.slv_reqs[2] = tb.dut.arbiter_inst.slv2_req_i;
  assign arb_if.a2s_acks[0] = tb.dut.arbiter_inst.a2s0_ack_o;
  assign arb_if.a2s_acks[1] = tb.dut.arbiter_inst.a2s1_ack_o;
  assign arb_if.a2s_acks[2] = tb.dut.arbiter_inst.a2s2_ack_o;
  assign arb_if.f2a_id_req = tb.dut.arbiter_inst.f2a_id_req_i;

  initial begin 
    // do interface configuration from top tb (HW) to verification env (SW)
    // 若传送的是句柄类型，需保证set/get传递的类型严格一致：若set是子类的类型，get是父类的类型，需要通过$cast进行类型转换后再进行传递
	uvm_config_db#(virtual chnl_intf)::set(uvm_root::get(), "uvm_test_top", "ch0_vif", chnl0_if);
    uvm_config_db#(virtual chnl_intf)::set(uvm_root::get(), "uvm_test_top", "ch1_vif", chnl1_if);
    uvm_config_db#(virtual chnl_intf)::set(uvm_root::get(), "uvm_test_top", "ch2_vif", chnl2_if);
    uvm_config_db#(virtual reg_intf)::set(uvm_root::get(), "uvm_test_top", "reg_vif", reg_if);
    uvm_config_db#(virtual arb_intf)::set(uvm_root::get(), "uvm_test_top", "arb_vif", arb_if);
    uvm_config_db#(virtual fmt_intf)::set(uvm_root::get(), "uvm_test_top", "fmt_vif", fmt_if);
    uvm_config_db#(virtual mcdf_intf)::set(uvm_root::get(), "uvm_test_top", "mcdf_vif", mcdf_if);
    // If no external configured via +UVM_TESTNAME=my_test, the default test is
    // mcdf_data_consistence_basic_test
    run_test("mcdf_data_consistence_basic_test");
  end
endmodule



