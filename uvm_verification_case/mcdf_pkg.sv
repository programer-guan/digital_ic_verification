`include "param_def.v"

package mcdf_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import chnl_pkg::*;
  import reg_pkg::*;
  import arb_pkg::*;
  import fmt_pkg::*;
  import mcdf_rgm_pkg::*;

  typedef struct packed {
    bit[2:0] len;
    bit[1:0] prio;
    bit en;
    bit[7:0] avail;
  } mcdf_reg_t;

  typedef enum {RW_LEN, RW_PRIO, RW_EN, RD_AVAIL} mcdf_field_t;

  // MCDF reference model
  class mcdf_refmod extends uvm_component;
    local virtual mcdf_intf intf;
    mcdf_reg_t regs[3];

    uvm_blocking_get_port #(reg_trans) reg_bg_port;
    uvm_blocking_get_peek_port #(mon_data_t) in_bgpk_ports[3];

    uvm_tlm_fifo #(fmt_trans) out_tlm_fifos[3];

    `uvm_component_utils(mcdf_refmod)

    function new (string name = "mcdf_refmod", uvm_component parent);
      super.new(name, parent);
      reg_bg_port = new("reg_bg_port", this);
      foreach(in_bgpk_ports[i]) in_bgpk_ports[i] = new($sformatf("in_bgpk_ports[%0d]", i), this);
      foreach(out_tlm_fifos[i]) out_tlm_fifos[i] = new($sformatf("out_tlm_fifos[%0d]", i), this);
    endfunction

    task run_phase(uvm_phase phase);
      fork
        do_reset();
        this.do_reg_update();
        do_packet(0);
        do_packet(1);
        do_packet(2);
      join
    endtask

    task do_reg_update();
      reg_trans t;
      forever begin
        this.reg_bg_port.get(t);
        if(t.addr[7:4] == 0 && t.cmd == `WRITE) begin
          this.regs[t.addr[3:2]].en = t.data[0];
          this.regs[t.addr[3:2]].prio = t.data[2:1];
          this.regs[t.addr[3:2]].len = t.data[5:3];
        end
        else if(t.addr[7:4] == 1 && t.cmd == `READ) begin
          this.regs[t.addr[3:2]].avail = t.data[7:0];
        end
      end
    endtask

    task do_packet(int id);
      fmt_trans ot;
      mon_data_t it;
      forever begin
        this.in_bgpk_ports[id].peek(it);
        ot = new();
        ot.length = 4 << (this.get_field_value(id, RW_LEN) & 'b11);
        ot.data = new[ot.length];
        ot.ch_id = id;
        foreach(ot.data[m]) begin
          this.in_bgpk_ports[id].get(it);
          ot.data[m] = it.data;
        end
        this.out_tlm_fifos[id].put(ot);
      end
    endtask

    function int get_field_value(int id, mcdf_field_t f);
      case(f)
        RW_LEN: return regs[id].len;
        RW_PRIO: return regs[id].prio;
        RW_EN: return regs[id].en;
        RD_AVAIL: return regs[id].avail;
      endcase
    endfunction 

    task do_reset();
      forever begin
        @(negedge intf.rstn); 
        foreach(regs[i]) begin
          regs[i].len = 'h0;
          regs[i].prio = 'h3;
          regs[i].en = 'h1;
          regs[i].avail = 'h20;
        end
      end
    endtask

    function void set_interface(virtual mcdf_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction
  endclass: mcdf_refmod

  // MCDF checker (scoreboard)

  `uvm_blocking_put_imp_decl(_chnl0)
  `uvm_blocking_put_imp_decl(_chnl1)
  `uvm_blocking_put_imp_decl(_chnl2)
  `uvm_blocking_put_imp_decl(_fmt)
  `uvm_blocking_put_imp_decl(_reg)

  `uvm_blocking_get_peek_imp_decl(_chnl0)
  `uvm_blocking_get_peek_imp_decl(_chnl1)
  `uvm_blocking_get_peek_imp_decl(_chnl2)

  `uvm_blocking_get_imp_decl(_reg)

  class mcdf_checker extends uvm_scoreboard;
    local int err_count;
    local int total_count;
    local int chnl_count[3];
    local virtual chnl_intf chnl_vifs[3]; 
    local virtual arb_intf arb_vif; 
    local virtual mcdf_intf mcdf_vif;
    local mcdf_refmod refmod;

    uvm_blocking_put_imp_chnl0 #(mon_data_t, mcdf_checker)   chnl0_bp_imp;
    uvm_blocking_put_imp_chnl1 #(mon_data_t, mcdf_checker)   chnl1_bp_imp;
    uvm_blocking_put_imp_chnl2 #(mon_data_t, mcdf_checker)   chnl2_bp_imp;
    uvm_blocking_put_imp_fmt   #(fmt_trans , mcdf_checker)   fmt_bp_imp  ;
    uvm_blocking_put_imp_reg   #(reg_trans , mcdf_checker)   reg_bp_imp  ;

    uvm_blocking_get_peek_imp_chnl0 #(mon_data_t, mcdf_checker)  chnl0_bgpk_imp;
    uvm_blocking_get_peek_imp_chnl1 #(mon_data_t, mcdf_checker)  chnl1_bgpk_imp;
    uvm_blocking_get_peek_imp_chnl2 #(mon_data_t, mcdf_checker)  chnl2_bgpk_imp;

    uvm_blocking_get_imp_reg    #(reg_trans , mcdf_checker)  reg_bg_imp  ;

    mailbox #(mon_data_t) chnl_mbs[3];
    mailbox #(fmt_trans)  fmt_mb;
    mailbox #(reg_trans)  reg_mb;

    uvm_blocking_get_port #(fmt_trans) exp_bg_ports[3];

    `uvm_component_utils(mcdf_checker)

    function new (string name = "mcdf_checker", uvm_component parent);
      super.new(name, parent);
      this.err_count = 0;
      this.total_count = 0;
      foreach(this.chnl_count[i]) this.chnl_count[i] = 0;

      chnl0_bp_imp = new("chnl0_bp_imp", this);
      chnl1_bp_imp = new("chnl1_bp_imp", this);
      chnl2_bp_imp = new("chnl2_bp_imp", this);
      fmt_bp_imp   = new("fmt_bp_imp", this);  
      reg_bp_imp   = new("reg_bp_imp", this);  

      chnl0_bgpk_imp = new("chnl0_bgpk_imp", this);
      chnl1_bgpk_imp = new("chnl1_bgpk_imp", this);
      chnl2_bgpk_imp = new("chnl2_bgpk_imp", this);

      reg_bg_imp    = new("reg_bg_imp", this);  

      foreach(exp_bg_ports[i]) exp_bg_ports[i] = new($sformatf("exp_bg_ports[%0d]", i), this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      foreach(this.chnl_mbs[i]) this.chnl_mbs[i] = new();
      this.fmt_mb = new();
      this.reg_mb = new();
      this.refmod = mcdf_refmod::type_id::create("refmod", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      refmod.in_bgpk_ports[0].connect(chnl0_bgpk_imp);
      refmod.in_bgpk_ports[1].connect(chnl1_bgpk_imp);
      refmod.in_bgpk_ports[2].connect(chnl2_bgpk_imp);

      refmod.reg_bg_port.connect(reg_bg_imp);

      foreach(exp_bg_ports[i]) begin
        exp_bg_ports[i].connect(refmod.out_tlm_fifos[i].blocking_get_export);
      end
    endfunction

    function void set_interface(virtual mcdf_intf mcdf_vif, virtual chnl_intf chnl_vifs[3], virtual arb_intf arb_vif);
      if(mcdf_vif == null)
        $error("mcdf interface handle is NULL, please check if target interface has been intantiated");
      else begin
        this.mcdf_vif = mcdf_vif;
        this.refmod.set_interface(mcdf_vif);
      end
      if(chnl_vifs[0] == null || chnl_vifs[1] == null || chnl_vifs[2] == null)
        $error("chnl interface handle is NULL, please check if target interface has been intantiated");
      else begin
        this.chnl_vifs = chnl_vifs;
      end
      if(arb_vif == null)
        $error("arb interface handle is NULL, please check if target interface has been intantiated");
      else begin
        this.arb_vif = arb_vif;
      end
    endfunction

    task run_phase(uvm_phase phase);
      fork
        this.do_channel_disable_check(0);
        this.do_channel_disable_check(1);
        this.do_channel_disable_check(2);
        this.do_arbiter_priority_check();
        this.do_data_compare();
        this.refmod.run();
      join
    endtask

    task do_data_compare();
      fmt_trans expt, mont;
      bit cmp;
      forever begin
        this.fmt_mb.get(mont);
        this.exp_bg_ports[mont.ch_id].get(expt);
        cmp = mont.compare(expt);   
        this.total_count++;
        this.chnl_count[mont.ch_id]++;
        if(cmp == 0) begin
          this.err_count++;
          `uvm_error("[CMPERR]", $sformatf("%0dth times comparing but failed! MCDF monitored output packet is different with reference model output", this.total_count))
        end
        else begin
          `uvm_info("[CMPSUC]",$sformatf("%0dth times comparing and succeeded! MCDF monitored output packet is the same with reference model output", this.total_count), UVM_LOW)
        end
      end
    endtask

    task do_channel_disable_check(int id);
      forever begin
        @(posedge this.mcdf_vif.clk iff (this.mcdf_vif.rstn && this.mcdf_vif.mon_ck.chnl_en[id]===0));
        if(this.chnl_vifs[id].mon_ck.ch_valid===1 && this.chnl_vifs[id].mon_ck.ch_ready===1)
          `uvm_error("[CHKERR]", "ERROR! when channel disabled, ready signal raised when valid high") 
      end
    endtask

    task do_arbiter_priority_check();
      int id;
      forever begin
        @(posedge this.arb_vif.clk iff (this.arb_vif.rstn && this.arb_vif.mon_ck.f2a_id_req===1));
        id = this.get_slave_id_with_prio();
        if(id >= 0) begin
          @(posedge this.arb_vif.clk);
          if(this.arb_vif.mon_ck.a2s_acks[id] !== 1)
            `uvm_error("[CHKERR]", $sformatf("ERROR! arbiter received f2a_id_req===1 and channel[%0d] raising request with high priority, but is not granted by arbiter", id))
        end
      end
    endtask

    function int get_slave_id_with_prio();
      int id=-1;
      int prio=999;
      foreach(this.arb_vif.mon_ck.slv_prios[i]) begin
        if(this.arb_vif.mon_ck.slv_prios[i] < prio && this.arb_vif.mon_ck.slv_reqs[i]===1) begin
          id = i;
          prio = this.arb_vif.mon_ck.slv_prios[i];
        end
      end
      return id;
    endfunction

    function void report_phase(uvm_phase phase);
      string s;
      super.report_phase(phase);
      s = "\n---------------------------------------------------------------\n";
      s = {s, "CHECKER SUMMARY \n"}; 
      s = {s, $sformatf("total comparison count: %0d \n", this.total_count)}; 
      foreach(this.chnl_count[i]) s = {s, $sformatf(" channel[%0d] comparison count: %0d \n", i, this.chnl_count[i])};
      s = {s, $sformatf("total error count: %0d \n", this.err_count)}; 
      foreach(this.chnl_mbs[i]) begin
        if(this.chnl_mbs[i].num() != 0)
          s = {s, $sformatf("WARNING:: chnl_mbs[%0d] is not empty! size = %0d \n", i, this.chnl_mbs[i].num())}; 
      end
      if(this.fmt_mb.num() != 0)
          s = {s, $sformatf("WARNING:: fmt_mb is not empty! size = %0d \n", this.fmt_mb.num())}; 
      s = {s, "---------------------------------------------------------------\n"};
      `uvm_info(get_type_name(), s, UVM_LOW)
    endfunction

    task put_chnl0(mon_data_t t);
      chnl_mbs[0].put(t);
    endtask
    task put_chnl1(mon_data_t t);
      chnl_mbs[1].put(t);
    endtask
    task put_chnl2(mon_data_t t);
      chnl_mbs[2].put(t);
    endtask
    task put_fmt(fmt_trans t);
      fmt_mb.put(t);
    endtask
    task put_reg(reg_trans t);
      reg_mb.put(t);
    endtask
    task peek_chnl0(output mon_data_t t);
      chnl_mbs[0].peek(t);
    endtask
    task peek_chnl1(output mon_data_t t);
      chnl_mbs[1].peek(t);
    endtask
    task peek_chnl2(output mon_data_t t);
      chnl_mbs[2].peek(t);
    endtask
    task get_chnl0(output mon_data_t t);
      chnl_mbs[0].get(t);
    endtask
    task get_chnl1(output mon_data_t t);
      chnl_mbs[1].get(t);
    endtask
    task get_chnl2(output mon_data_t t);
      chnl_mbs[2].get(t);
    endtask
    task get_reg(output reg_trans t);
      reg_mb.get(t);
    endtask
  endclass: mcdf_checker

  // MCDF coverage model
  class mcdf_coverage extends uvm_component;
    local virtual chnl_intf chnl_vifs[3]; 
    local virtual arb_intf arb_vif; 
    local virtual mcdf_intf mcdf_vif;
    local virtual reg_intf reg_vif;
    local virtual fmt_intf fmt_vif;
    local int delay_req_to_grant;

    `uvm_component_utils(mcdf_coverage)

    covergroup cg_mcdf_reg_write_read;
      addr: coverpoint reg_vif.mon_ck.cmd_addr {
        type_option.weight = 0;
        bins slv0_rw_addr = {`SLV0_RW_ADDR};
        bins slv1_rw_addr = {`SLV1_RW_ADDR};
        bins slv2_rw_addr = {`SLV2_RW_ADDR};
        bins slv0_r_addr  = {`SLV0_R_ADDR };
        bins slv1_r_addr  = {`SLV1_R_ADDR };
        bins slv2_r_addr  = {`SLV2_R_ADDR };
      }
      cmd: coverpoint reg_vif.mon_ck.cmd {
        type_option.weight = 0;
        bins write = {`WRITE};
        bins read  = {`READ};
        bins idle  = {`IDLE};
      }
      cmdXaddr: cross cmd, addr {
        bins slv0_rw_addr = binsof(addr.slv0_rw_addr);
        bins slv1_rw_addr = binsof(addr.slv1_rw_addr);
        bins slv2_rw_addr = binsof(addr.slv2_rw_addr);
        bins slv0_r_addr  = binsof(addr.slv0_r_addr );
        bins slv1_r_addr  = binsof(addr.slv1_r_addr );
        bins slv2_r_addr  = binsof(addr.slv2_r_addr );
        bins write        = binsof(cmd.write);
        bins read         = binsof(cmd.read );
        bins idle         = binsof(cmd.idle );
        bins write_slv0_rw_addr  = binsof(cmd.write) && binsof(addr.slv0_rw_addr);
        bins write_slv1_rw_addr  = binsof(cmd.write) && binsof(addr.slv1_rw_addr);
        bins write_slv2_rw_addr  = binsof(cmd.write) && binsof(addr.slv2_rw_addr);
        bins read_slv0_rw_addr   = binsof(cmd.read) && binsof(addr.slv0_rw_addr);
        bins read_slv1_rw_addr   = binsof(cmd.read) && binsof(addr.slv1_rw_addr);
        bins read_slv2_rw_addr   = binsof(cmd.read) && binsof(addr.slv2_rw_addr);
        bins read_slv0_r_addr    = binsof(cmd.read) && binsof(addr.slv0_r_addr); 
        bins read_slv1_r_addr    = binsof(cmd.read) && binsof(addr.slv1_r_addr); 
        bins read_slv2_r_addr    = binsof(cmd.read) && binsof(addr.slv2_r_addr); 
      }
    endgroup

    covergroup cg_mcdf_reg_illegal_access;
      addr: coverpoint reg_vif.mon_ck.cmd_addr {
        type_option.weight = 0;
        bins legal_rw = {`SLV0_RW_ADDR, `SLV1_RW_ADDR, `SLV2_RW_ADDR};
        bins legal_r = {`SLV0_R_ADDR, `SLV1_R_ADDR, `SLV2_R_ADDR};
        bins illegal = {[8'h20:$], 8'hC, 8'h1C};
      }
      cmd: coverpoint reg_vif.mon_ck.cmd {
        type_option.weight = 0;
        bins write = {`WRITE};
        bins read  = {`READ};
      }
      wdata: coverpoint reg_vif.mon_ck.cmd_data_m2s {
        type_option.weight = 0;
        bins legal = {[0:'h3F]};
        bins illegal = {['h40:$]};
      }
      rdata: coverpoint reg_vif.mon_ck.cmd_data_s2m {
        type_option.weight = 0;
        bins legal = {[0:'hFF]};
        illegal_bins illegal = default;
      }
      cmdXaddrXdata: cross cmd, addr, wdata, rdata {
        bins addr_legal_rw = binsof(addr.legal_rw);
        bins addr_legal_r = binsof(addr.legal_r);
        bins addr_illegal = binsof(addr.illegal);
        bins cmd_write = binsof(cmd.write);
        bins cmd_read = binsof(cmd.read);
        bins wdata_legal = binsof(wdata.legal);
        bins wdata_illegal = binsof(wdata.illegal);
        bins rdata_legal = binsof(rdata.legal);
        bins write_illegal_addr = binsof(cmd.write) && binsof(addr.illegal);
        bins read_illegal_addr  = binsof(cmd.read) && binsof(addr.illegal);
        bins write_illegal_rw_data = binsof(cmd.write) && binsof(addr.legal_rw) && binsof(wdata.illegal);
        bins write_illegal_r_data = binsof(cmd.write) && binsof(addr.legal_r) && binsof(wdata.illegal);
      }
    endgroup

    covergroup cg_channel_disable;
      ch0_en: coverpoint mcdf_vif.mon_ck.chnl_en[0] {
        type_option.weight = 0;
        wildcard bins en  = {1'b1};
        wildcard bins dis = {1'b0};
      }
      ch1_en: coverpoint mcdf_vif.mon_ck.chnl_en[1] {
        type_option.weight = 0;
        wildcard bins en  = {1'b1};
        wildcard bins dis = {1'b0};
      }
      ch2_en: coverpoint mcdf_vif.mon_ck.chnl_en[2] {
        type_option.weight = 0;
        wildcard bins en  = {1'b1};
        wildcard bins dis = {1'b0};
      }
      ch0_vld: coverpoint chnl_vifs[0].mon_ck.ch_valid {
        type_option.weight = 0;
        bins hi = {1'b1};
        bins lo = {1'b0};
      }
      ch1_vld: coverpoint chnl_vifs[1].mon_ck.ch_valid {
        type_option.weight = 0;
        bins hi = {1'b1};
        bins lo = {1'b0};
      }
      ch2_vld: coverpoint chnl_vifs[2].mon_ck.ch_valid {
        type_option.weight = 0;
        bins hi = {1'b1};
        bins lo = {1'b0};
      }
      chenXchvld: cross ch0_en, ch1_en, ch2_en, ch0_vld, ch1_vld, ch2_vld {
        bins ch0_en  = binsof(ch0_en.en);
        bins ch0_dis = binsof(ch0_en.dis);
        bins ch1_en  = binsof(ch1_en.en);
        bins ch1_dis = binsof(ch1_en.dis);
        bins ch2_en  = binsof(ch2_en.en);
        bins ch2_dis = binsof(ch2_en.dis);
        bins ch0_hi  = binsof(ch0_vld.hi);
        bins ch0_lo  = binsof(ch0_vld.lo);
        bins ch1_hi  = binsof(ch1_vld.hi);
        bins ch1_lo  = binsof(ch1_vld.lo);
        bins ch2_hi  = binsof(ch2_vld.hi);
        bins ch2_lo  = binsof(ch2_vld.lo);
        bins ch0_en_vld = binsof(ch0_en.en) && binsof(ch0_vld.hi);
        bins ch0_dis_vld = binsof(ch0_en.dis) && binsof(ch0_vld.hi);
        bins ch1_en_vld = binsof(ch1_en.en) && binsof(ch1_vld.hi);
        bins ch1_dis_vld = binsof(ch1_en.dis) && binsof(ch1_vld.hi);
        bins ch2_en_vld = binsof(ch2_en.en) && binsof(ch2_vld.hi);
        bins ch2_dis_vld = binsof(ch2_en.dis) && binsof(ch2_vld.hi);
      }
    endgroup

    covergroup cg_arbiter_priority;
      ch0_prio: coverpoint arb_vif.mon_ck.slv_prios[0] {
        bins ch_prio0 = {0}; 
        bins ch_prio1 = {1}; 
        bins ch_prio2 = {2}; 
        bins ch_prio3 = {3}; 
      }
      ch1_prio: coverpoint arb_vif.mon_ck.slv_prios[1] {
        bins ch_prio0 = {0}; 
        bins ch_prio1 = {1}; 
        bins ch_prio2 = {2}; 
        bins ch_prio3 = {3}; 
      }
      ch2_prio: coverpoint arb_vif.mon_ck.slv_prios[2] {
        bins ch_prio0 = {0}; 
        bins ch_prio1 = {1}; 
        bins ch_prio2 = {2}; 
        bins ch_prio3 = {3}; 
      }
    endgroup

    covergroup cg_formatter_length;
      id: coverpoint fmt_vif.mon_ck.fmt_chid {
        bins ch0 = {0};
        bins ch1 = {1};
        bins ch2 = {2};
        illegal_bins illegal = default; 
      }
      length: coverpoint fmt_vif.mon_ck.fmt_length {
        bins len4  = {4};
        bins len8  = {8};
        bins len16 = {16};
        bins len32 = {32};
        illegal_bins illegal = default;
      }
    endgroup

    covergroup cg_formatter_grant();
      delay_req_to_grant: coverpoint this.delay_req_to_grant {
        bins delay1 = {1};
        bins delay2 = {2};
        bins delay3_or_more = {[3:10]};
        illegal_bins illegal = {0};
      }
    endgroup

    function new (string name = "mcdf_coverage", uvm_component parent);
      super.new(name, parent);
      this.cg_mcdf_reg_write_read = new();
      this.cg_mcdf_reg_illegal_access = new();
      this.cg_channel_disable = new();
      this.cg_arbiter_priority = new();
      this.cg_formatter_length = new();
      this.cg_formatter_grant = new();
    endfunction

    task run_phase(uvm_phase phase);
      fork 
        this.do_reg_sample();
        this.do_channel_sample();
        this.do_arbiter_sample();
        this.do_formater_sample();
      join
    endtask

    task do_reg_sample();
      forever begin
        @(posedge reg_vif.clk iff reg_vif.rstn);
        this.cg_mcdf_reg_write_read.sample();
        this.cg_mcdf_reg_illegal_access.sample();
      end
    endtask

    task do_channel_sample();
      forever begin
        @(posedge mcdf_vif.clk iff mcdf_vif.rstn);
        if(chnl_vifs[0].mon_ck.ch_valid===1
          || chnl_vifs[1].mon_ck.ch_valid===1
          || chnl_vifs[2].mon_ck.ch_valid===1)
          this.cg_channel_disable.sample();
      end
    endtask

    task do_arbiter_sample();
      forever begin
        @(posedge arb_vif.clk iff arb_vif.rstn);
        if(arb_vif.slv_reqs[0]!==0 || arb_vif.slv_reqs[1]!==0 || arb_vif.slv_reqs[2]!==0)
          this.cg_arbiter_priority.sample();
      end
    endtask

    task do_formater_sample();
      fork
        forever begin
          @(posedge fmt_vif.clk iff fmt_vif.rstn);
          if(fmt_vif.mon_ck.fmt_req === 1)
            this.cg_formatter_length.sample();
        end
        forever begin
          @(posedge fmt_vif.mon_ck.fmt_req);
          this.delay_req_to_grant = 0;
          forever begin
            if(fmt_vif.fmt_grant === 1) begin
              this.cg_formatter_grant.sample();
              break;
            end
            else begin
              @(posedge fmt_vif.clk);
              this.delay_req_to_grant++;
            end
          end
        end
      join
    endtask

    function void report_phase(uvm_phase phase);
      string s;
      super.report_phase(phase);
      s = "\n---------------------------------------------------------------\n";
      s = {s, "COVERAGE SUMMARY \n"}; 
      s = {s, $sformatf("total coverage: %.1f \n", $get_coverage())}; 
      s = {s, $sformatf("  cg_mcdf_reg_write_read coverage: %.1f \n", this.cg_mcdf_reg_write_read.get_coverage())}; 
      s = {s, $sformatf("  cg_mcdf_reg_illegal_access coverage: %.1f \n", this.cg_mcdf_reg_illegal_access.get_coverage())}; 
      s = {s, $sformatf("  cg_channel_disable_test coverage: %.1f \n", this.cg_channel_disable.get_coverage())}; 
      s = {s, $sformatf("  cg_arbiter_priority_test coverage: %.1f \n", this.cg_arbiter_priority.get_coverage())}; 
      s = {s, $sformatf("  cg_formatter_length_test coverage: %.1f \n", this.cg_formatter_length.get_coverage())}; 
      s = {s, $sformatf("  cg_formatter_grant_test coverage: %.1f \n", this.cg_formatter_grant.get_coverage())}; 
      s = {s, "---------------------------------------------------------------\n"};
      `uvm_info(get_type_name(), s, UVM_LOW)
    endfunction

    virtual function void set_interface(virtual chnl_intf ch_vifs[3] 
                                        ,virtual reg_intf reg_vif
                                        ,virtual arb_intf arb_vif
                                        ,virtual fmt_intf fmt_vif
                                        ,virtual mcdf_intf mcdf_vif
                                      );
      this.chnl_vifs = ch_vifs;
      this.arb_vif = arb_vif;
      this.reg_vif = reg_vif;
      this.fmt_vif = fmt_vif;
      this.mcdf_vif = mcdf_vif;
      if(chnl_vifs[0] == null || chnl_vifs[1] == null || chnl_vifs[2] == null)
        $error("chnl interface handle is NULL, please check if target interface has been intantiated");
      if(arb_vif == null)
        $error("arb interface handle is NULL, please check if target interface has been intantiated");
      if(reg_vif == null)
        $error("reg interface handle is NULL, please check if target interface has been intantiated");
      if(fmt_vif == null)
        $error("fmt interface handle is NULL, please check if target interface has been intantiated");
      if(mcdf_vif == null)
        $error("mcdf interface handle is NULL, please check if target interface has been intantiated");
    endfunction
  endclass: mcdf_coverage

  class mcdf_virtual_sequencer extends uvm_sequencer;
    reg_sequencer reg_sqr;
    fmt_sequencer fmt_sqr;
    chnl_sequencer chnl_sqrs[3];
    mcdf_rgm rgm;
    virtual mcdf_intf intf;
    `uvm_component_utils(mcdf_virtual_sequencer)
    function new (string name = "mcdf_virtual_sequencer", uvm_component parent);
      super.new(name, parent);
    endfunction
    function void set_interface(virtual mcdf_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction
  endclass

  // MCDF top environment
  class mcdf_env extends uvm_env;
    chnl_agent chnl_agts[3];
    reg_agent reg_agt;
    fmt_agent fmt_agt;
    mcdf_checker chker;
    mcdf_coverage cvrg;
    mcdf_virtual_sequencer virt_sqr;
    //TODO-1.2 declare the mcdf_rgm handle, reg2mcdf_adapter handle and the
    //predictory handle
    uvm_reg_predictor #(reg_trans) predictor;

    `uvm_component_utils(mcdf_env)

    function new (string name = "mcdf_env", uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      this.chker = mcdf_checker::type_id::create("chker", this);
      foreach(chnl_agts[i]) begin
        this.chnl_agts[i] = chnl_agent::type_id::create($sformatf("chnl_agts[%0d]",i), this);
      end
      this.reg_agt = reg_agent::type_id::create("reg_agt", this);
      this.fmt_agt = fmt_agent::type_id::create("fmt_agt", this);
      this.cvrg = mcdf_coverage::type_id::create("cvrg", this);
      virt_sqr = mcdf_virtual_sequencer::type_id::create("virt_sqr", this);
      //TODO-1.2 instantiate those objects
      //  -mcdf_rgm object
      //  -reg2mcdf_adapter object
      //  -predictory object
      //and finish necessary configuration 
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      chnl_agts[0].monitor.mon_bp_port.connect(chker.chnl0_bp_imp);
      chnl_agts[1].monitor.mon_bp_port.connect(chker.chnl1_bp_imp);
      chnl_agts[2].monitor.mon_bp_port.connect(chker.chnl2_bp_imp);
      reg_agt.monitor.mon_bp_port.connect(chker.reg_bp_imp);
      fmt_agt.monitor.mon_bp_port.connect(chker.fmt_bp_imp);
      virt_sqr.reg_sqr = reg_agt.sequencer;
      virt_sqr.fmt_sqr = fmt_agt.sequencer;
      foreach(virt_sqr.chnl_sqrs[i]) virt_sqr.chnl_sqrs[i] = chnl_agts[i].sequencer;
      //TODO-1.2 Link the register model with the adapter and the predictor

      //TODO-2.1 connect the virtual sequencer's rgm handle with rgm object
      //build已使用了自顶而下的方式, 创建了环境的所有子组件,所以在调用connect()时,用户可创建测试/环境/组件之间的层次化拓扑结构
      uvm_top.print_topology(); 
    endfunction
  endclass: mcdf_env

  class mcdf_base_virtual_sequence extends uvm_sequence;
    idle_reg_sequence idle_reg_seq;
    write_reg_sequence write_reg_seq;
    read_reg_sequence read_reg_seq;
    chnl_data_sequence chnl_data_seq;
    fmt_config_sequence fmt_config_seq;
    mcdf_rgm rgm;

    `uvm_object_utils(mcdf_base_virtual_sequence)
    `uvm_declare_p_sequencer(mcdf_virtual_sequencer)

    function new (string name = "mcdf_base_virtual_sequence");
      super.new(name);
    endfunction

    virtual task body();
      `uvm_info(get_type_name(), "=====================STARTED=====================", UVM_LOW)
      //TODO-2.1 connect rgm handle

      this.do_reg();
      this.do_formatter();
      this.do_data();

      `uvm_info(get_type_name(), "=====================FINISHED=====================", UVM_LOW)
    endtask

    // do register configuration
    virtual task do_reg();
      //User to implment the task in the child virtual sequence
    endtask

    // do external formatter down stream slave configuration
    virtual task do_formatter();
      //User to implment the task in the child virtual sequence
    endtask

    // do data transition from 3 channel slaves
    virtual task do_data();
      //User to implment the task in the child virtual sequence
    endtask

    virtual function bit diff_value(int val1, int val2, string id = "value_compare");
      if(val1 != val2) begin
        `uvm_error("[CMPERR]", $sformatf("ERROR! %s val1 %8x != val2 %8x", id, val1, val2)) 
        return 0;
      end
      else begin
        `uvm_info("[CMPSUC]", $sformatf("SUCCESS! %s val1 %8x == val2 %8x", id, val1, val2), UVM_LOW)
        return 1;
      end
    endfunction
  endclass

  // MCDF base test
  class mcdf_base_test extends uvm_test;
    mcdf_env env;
    virtual chnl_intf ch0_vif ;
    virtual chnl_intf ch1_vif ;
    virtual chnl_intf ch2_vif ;
    virtual reg_intf reg_vif  ;
    virtual arb_intf arb_vif  ;
    virtual fmt_intf fmt_vif  ;
    virtual mcdf_intf mcdf_vif;

    `uvm_component_utils(mcdf_base_test)

    function new(string name = "mcdf_base_test", uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      // get virtual interface from top TB
      if(!uvm_config_db#(virtual chnl_intf)::get(this,"","ch0_vif", ch0_vif)) begin
        `uvm_fatal("GETVIF","cannot get vif handle from config DB")
      end
      if(!uvm_config_db#(virtual chnl_intf)::get(this,"","ch1_vif", ch1_vif)) begin
        `uvm_fatal("GETVIF","cannot get vif handle from config DB")
      end
      if(!uvm_config_db#(virtual chnl_intf)::get(this,"","ch2_vif", ch2_vif)) begin
        `uvm_fatal("GETVIF","cannot get vif handle from config DB")
      end
      if(!uvm_config_db#(virtual reg_intf)::get(this,"","reg_vif", reg_vif)) begin
        `uvm_fatal("GETVIF","cannot get vif handle from config DB")
      end
      if(!uvm_config_db#(virtual arb_intf)::get(this,"","arb_vif", arb_vif)) begin
        `uvm_fatal("GETVIF","cannot get vif handle from config DB")
      end
      if(!uvm_config_db#(virtual fmt_intf)::get(this,"","fmt_vif", fmt_vif)) begin
        `uvm_fatal("GETVIF","cannot get vif handle from config DB")
      end
      if(!uvm_config_db#(virtual mcdf_intf)::get(this,"","mcdf_vif", mcdf_vif)) begin
        `uvm_fatal("GETVIF","cannot get vif handle from config DB")
      end

      this.env = mcdf_env::type_id::create("env", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      // After get virtual interface from config_db, and then set them to
      // child components
      this.set_interface(ch0_vif, ch1_vif, ch2_vif, reg_vif, arb_vif, fmt_vif, mcdf_vif);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      uvm_root::get().set_report_verbosity_level_hier(UVM_HIGH);
      uvm_root::get().set_report_max_quit_count(1);
      uvm_root::get().set_timeout(10ms);
    endfunction

    task run_phase(uvm_phase phase);
      // NOTE:: raise objection to prevent simulation stopping
      phase.raise_objection(this);

      this.run_top_virtual_sequence();

      // NOTE:: drop objection to request simulation stopping
      phase.drop_objection(this);
    endtask

    virtual task run_top_virtual_sequence();
      // User to implement this task in the child tests
    endtask

    virtual function void set_interface(virtual chnl_intf ch0_vif 
                                        ,virtual chnl_intf ch1_vif 
                                        ,virtual chnl_intf ch2_vif 
                                        ,virtual reg_intf reg_vif
                                        ,virtual arb_intf arb_vif
                                        ,virtual fmt_intf fmt_vif
                                        ,virtual mcdf_intf mcdf_vif
                                      );
      this.env.chnl_agts[0].set_interface(ch0_vif);
      this.env.chnl_agts[1].set_interface(ch1_vif);
      this.env.chnl_agts[2].set_interface(ch2_vif);
      this.env.reg_agt.set_interface(reg_vif);
      this.env.fmt_agt.set_interface(fmt_vif);
      this.env.chker.set_interface(mcdf_vif, '{ch0_vif, ch1_vif, ch2_vif}, arb_vif);
      this.env.cvrg.set_interface('{ch0_vif, ch1_vif, ch2_vif}, reg_vif, arb_vif, fmt_vif, mcdf_vif);
      this.env.virt_sqr.set_interface(mcdf_vif);
    endfunction
  endclass: mcdf_base_test

  //TODO-2.2 replace the register bus sequence with uvm_reg::write()/read()
  class mcdf_data_consistence_basic_virtual_sequence extends mcdf_base_virtual_sequence;
    `uvm_object_utils(mcdf_data_consistence_basic_virtual_sequence)
    function new (string name = "mcdf_data_consistence_basic_virtual_sequence");
      super.new(name);
    endfunction
    task do_reg();
      bit[31:0] wr_val, rd_val;
      // slv0 with len=8,  prio=0, en=1
      wr_val = (1<<3)+(0<<1)+1;
      `uvm_do_on_with(write_reg_seq, p_sequencer.reg_sqr, {addr == `SLV0_RW_ADDR; data == wr_val;})
      `uvm_do_on_with(read_reg_seq, p_sequencer.reg_sqr, {addr == `SLV0_RW_ADDR;})
      rd_val = read_reg_seq.data;
      void'(this.diff_value(wr_val, rd_val, "SLV0_WR_REG"));

      // slv1 with len=16, prio=1, en=1
      wr_val = (2<<3)+(1<<1)+1;
      `uvm_do_on_with(write_reg_seq, p_sequencer.reg_sqr, {addr == `SLV1_RW_ADDR; data == wr_val;})
      `uvm_do_on_with(read_reg_seq, p_sequencer.reg_sqr, {addr == `SLV1_RW_ADDR;})
      rd_val = read_reg_seq.data;
      void'(this.diff_value(wr_val, rd_val, "SLV1_WR_REG"));

      // slv2 with len=32, prio=2, en=1
      wr_val = (3<<3)+(2<<1)+1;
      `uvm_do_on_with(write_reg_seq, p_sequencer.reg_sqr, {addr == `SLV2_RW_ADDR; data == wr_val;})
      `uvm_do_on_with(read_reg_seq, p_sequencer.reg_sqr, {addr == `SLV2_RW_ADDR;})
      rd_val = read_reg_seq.data;
      void'(this.diff_value(wr_val, rd_val, "SLV2_WR_REG"));

      // send IDLE command
      `uvm_do_on(idle_reg_seq, p_sequencer.reg_sqr)
    endtask
    task do_formatter();
      `uvm_do_on_with(fmt_config_seq, p_sequencer.fmt_sqr, {fifo == LONG_FIFO; bandwidth == HIGH_WIDTH;})
    endtask
    task do_data();
      fork
        `uvm_do_on_with(chnl_data_seq, p_sequencer.chnl_sqrs[0], {ntrans==100; ch_id==0; data_nidles==0; pkt_nidles==1; data_size==8; })
        `uvm_do_on_with(chnl_data_seq, p_sequencer.chnl_sqrs[1], {ntrans==100; ch_id==1; data_nidles==1; pkt_nidles==4; data_size==16;})
        `uvm_do_on_with(chnl_data_seq, p_sequencer.chnl_sqrs[2], {ntrans==100; ch_id==2; data_nidles==2; pkt_nidles==8; data_size==32;})
      join
      #10us; // wait until all data haven been transfered through MCDF
    endtask
  endclass: mcdf_data_consistence_basic_virtual_sequence

  class mcdf_data_consistence_basic_test extends mcdf_base_test;

    `uvm_component_utils(mcdf_data_consistence_basic_test)

    function new(string name = "mcdf_data_consistence_basic_test", uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_top_virtual_sequence();
      mcdf_data_consistence_basic_virtual_sequence top_seq = new();
      top_seq.start(env.virt_sqr);
    endtask
  endclass: mcdf_data_consistence_basic_test

  //TODO-2.3 Follow the instructions below
  //  -reset the register block
  //  -set all value of WR registers via uvm_reg::set()
  //  -update them via uvm_reg_block::update()
  //  -compare the register value via uvm_reg::mirror()
  class mcdf_full_random_virtual_sequence extends mcdf_base_virtual_sequence;
    `uvm_object_utils(mcdf_base_virtual_sequence)
    function new (string name = "mcdf_base_virtual_sequence");
      super.new(name);
    endfunction

    task do_reg();
      bit[31:0] wr_val, rd_val;
      // slv0 with len={4,8,16,32},  prio={[0:3]}, en={[0:1]}
      wr_val = ($urandom_range(0,3)<<3)+($urandom_range(0,3)<<1)+$urandom_range(0,1);
      `uvm_do_on_with(write_reg_seq, p_sequencer.reg_sqr, {addr == `SLV0_RW_ADDR; data == wr_val;})
      `uvm_do_on_with(read_reg_seq, p_sequencer.reg_sqr, {addr == `SLV0_RW_ADDR;})
      rd_val = read_reg_seq.data;
      void'(this.diff_value(wr_val, rd_val, "SLV0_WR_REG"));

      // slv0 with len={4,8,16,32},  prio={[0:3]}, en={[0:1]}
      wr_val = ($urandom_range(0,3)<<3)+($urandom_range(0,3)<<1)+$urandom_range(0,1);
      `uvm_do_on_with(write_reg_seq, p_sequencer.reg_sqr, {addr == `SLV1_RW_ADDR; data == wr_val;})
      `uvm_do_on_with(read_reg_seq, p_sequencer.reg_sqr, {addr == `SLV1_RW_ADDR;})
      rd_val = read_reg_seq.data;
      void'(this.diff_value(wr_val, rd_val, "SLV1_WR_REG"));

      // slv0 with len={4,8,16,32},  prio={[0:3]}, en={[0:1]}
      wr_val = ($urandom_range(0,3)<<3)+($urandom_range(0,3)<<1)+$urandom_range(0,1);
      `uvm_do_on_with(write_reg_seq, p_sequencer.reg_sqr, {addr == `SLV2_RW_ADDR; data == wr_val;})
      `uvm_do_on_with(read_reg_seq, p_sequencer.reg_sqr, {addr == `SLV2_RW_ADDR;})
      rd_val = read_reg_seq.data;
      void'(this.diff_value(wr_val, rd_val, "SLV2_WR_REG"));

      // send IDLE command
      `uvm_do_on(idle_reg_seq, p_sequencer.reg_sqr)
    endtask
    task do_formatter();
      `uvm_do_on_with(fmt_config_seq, p_sequencer.fmt_sqr, {fifo inside {SHORT_FIFO, ULTRA_FIFO}; bandwidth inside {LOW_WIDTH, ULTRA_WIDTH};})
    endtask
    task do_data();
      fork
        `uvm_do_on_with(chnl_data_seq, p_sequencer.chnl_sqrs[0], 
          {ntrans inside {[400:600]}; ch_id==0; data_nidles inside {[0:3]}; pkt_nidles inside {1,2,4,8}; data_size inside {8,16,32};})
        `uvm_do_on_with(chnl_data_seq, p_sequencer.chnl_sqrs[1], 
          {ntrans inside {[400:600]}; ch_id==0; data_nidles inside {[0:3]}; pkt_nidles inside {1,2,4,8}; data_size inside {8,16,32};})
        `uvm_do_on_with(chnl_data_seq, p_sequencer.chnl_sqrs[2], 
          {ntrans inside {[400:600]}; ch_id==0; data_nidles inside {[0:3]}; pkt_nidles inside {1,2,4,8}; data_size inside {8,16,32};})
      join
      #10us; // wait until all data haven been transfered through MCDF
    endtask
  endclass: mcdf_full_random_virtual_sequence

  class mcdf_full_random_test extends mcdf_base_test;

    `uvm_component_utils(mcdf_full_random_test)

    function new(string name = "mcdf_full_random_test", uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_top_virtual_sequence();
      mcdf_full_random_virtual_sequence top_seq = new();
      top_seq.start(env.virt_sqr);
    endtask
  endclass: mcdf_full_random_test


  //TODO-3.1 Use build-in uvm register sequence
  //  -uvm_reg_hw_reset_seq
  //  -uvm_reg_bit_bash_seq
  //  -uvm_reg_access_seq
  class mcdf_reg_builtin_virtual_sequence extends mcdf_base_virtual_sequence;
    `uvm_object_utils(mcdf_reg_builtin_virtual_sequence)
    function new (string name = "mcdf_reg_builtin_virtual_sequence");
      super.new(name);
    endfunction

    task do_reg();
      //USER TODO
    endtask
  endclass: mcdf_reg_builtin_virtual_sequence

  class mcdf_reg_builtin_test extends mcdf_base_test;

    `uvm_component_utils(mcdf_reg_builtin_test)

    function new(string name = "mcdf_reg_builtin_test", uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_top_virtual_sequence();
      mcdf_reg_builtin_virtual_sequence top_seq = new();
      top_seq.start(env.virt_sqr);
    endtask
  endclass: mcdf_reg_builtin_test

endpackage
