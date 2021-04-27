
package fmt_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum {SHORT_FIFO, MED_FIFO, LONG_FIFO, ULTRA_FIFO} fmt_fifo_t;
  typedef enum {LOW_WIDTH, MED_WIDTH, HIGH_WIDTH, ULTRA_WIDTH} fmt_bandwidth_t;

  // formatter sequence item
  class fmt_trans extends uvm_sequence_item;
    rand fmt_fifo_t fifo;
    rand fmt_bandwidth_t bandwidth;
    bit [9:0] length;
    bit [31:0] data[];
    bit [1:0] ch_id;
    bit rsp;

    constraint cstr{
      soft fifo == MED_FIFO;
      soft bandwidth == MED_WIDTH;
    };

    `uvm_object_utils_begin(fmt_trans)
      `uvm_field_enum(fmt_fifo_t, fifo, UVM_ALL_ON)
      `uvm_field_enum(fmt_bandwidth_t, bandwidth, UVM_ALL_ON)
      `uvm_field_int(length, UVM_ALL_ON)
      `uvm_field_array_int(data, UVM_ALL_ON)
      `uvm_field_int(ch_id, UVM_ALL_ON)
      `uvm_field_int(rsp, UVM_ALL_ON)
    `uvm_object_utils_end

    function new (string name = "fmt_trans");
      super.new(name);
    endfunction
  endclass

  // formatter driver
  class fmt_driver extends uvm_driver #(fmt_trans);
    local virtual fmt_intf intf;

    local mailbox #(bit[31:0]) fifo;
    local int fifo_bound;
    local int data_consum_peroid;

    `uvm_component_utils(fmt_driver)

    function new (string name = "fmt_driver", uvm_component parent);
      super.new(name, parent);
      this.fifo = new();
      this.fifo_bound = 4096;
      this.data_consum_peroid = 1;
    endfunction
  
    function void set_interface(virtual fmt_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction

    task run_phase(uvm_phase phase);
      fork
        this.do_receive();
        this.do_consume();
        this.do_config();
        this.do_reset();
      join
    endtask

    task do_config();
      fmt_trans req, rsp;
      forever begin
        seq_item_port.get_next_item(req);
        case(req.fifo)
          SHORT_FIFO: this.fifo_bound = 64;
          MED_FIFO: this.fifo_bound = 256;
          LONG_FIFO: this.fifo_bound = 512;
          ULTRA_FIFO: this.fifo_bound = 2048;
        endcase
        this.fifo = new(this.fifo_bound);
        case(req.bandwidth)
          LOW_WIDTH: this.data_consum_peroid = 8;
          MED_WIDTH: this.data_consum_peroid = 4;
          HIGH_WIDTH: this.data_consum_peroid = 2;
          ULTRA_WIDTH: this.data_consum_peroid = 1;
        endcase
		//copy默认创建好了对象，只需要对数据进行拷贝；
		//clone自动创建对象并对source obiect进行数据拷贝，再返回target object句柄
        void'($cast(rsp, req.clone()));
        rsp.rsp = 1;
        rsp.set_sequence_id(req.get_sequence_id());
        seq_item_port.item_done(rsp);
      end
    endtask

    task do_reset();
      forever begin
        @(negedge intf.rstn) 
        intf.fmt_grant <= 0;
      end
    endtask

    task do_receive();
      forever begin
        @(posedge intf.fmt_req);
        forever begin
          @(posedge intf.clk);
          if((this.fifo_bound-this.fifo.num()) >= intf.fmt_length)
            break;
        end
        intf.drv_ck.fmt_grant <= 1;
        @(posedge intf.fmt_start);
        fork
          begin
            @(posedge intf.clk);
            intf.drv_ck.fmt_grant <= 0;
          end
        join_none
        repeat(intf.fmt_length) begin
          @(negedge intf.clk);
          this.fifo.put(intf.fmt_data);
        end
      end
    endtask

    task do_consume();
      bit[31:0] data;
      forever begin
        void'(this.fifo.try_get(data));
        repeat($urandom_range(1, this.data_consum_peroid)) @(posedge intf.clk);
      end
    endtask
  endclass: fmt_driver

  class fmt_sequencer extends uvm_sequencer #(fmt_trans);
    `uvm_component_utils(fmt_sequencer)
    function new (string name = "fmt_sequencer", uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass: fmt_sequencer

  
  class fmt_config_sequence extends uvm_sequence #(fmt_trans);
    rand fmt_fifo_t fifo = MED_FIFO;
    rand fmt_bandwidth_t bandwidth = MED_WIDTH;
    constraint cstr{
      soft fifo == MED_FIFO;
      soft bandwidth == MED_WIDTH;
    }

    `uvm_object_utils_begin(fmt_config_sequence)
      `uvm_field_enum(fmt_fifo_t, fifo, UVM_ALL_ON)
      `uvm_field_enum(fmt_bandwidth_t, bandwidth, UVM_ALL_ON)
    `uvm_object_utils_end
    `uvm_declare_p_sequencer(fmt_sequencer)

    function new (string name = "fmt_config_sequence");
      super.new(name);
    endfunction

    task body();
      send_trans();
    endtask
    
    task send_trans();
      fmt_trans req, rsp;
      `uvm_do_with(req, {local::fifo != MED_FIFO -> fifo == local::fifo; 
                         local::bandwidth != MED_WIDTH -> bandwidth == local::bandwidth;
                        })
      `uvm_info(get_type_name(), req.sprint(), UVM_HIGH)
      get_response(rsp);
      `uvm_info(get_type_name(), rsp.sprint(), UVM_HIGH)
      assert(rsp.rsp)
        else $error("[RSPERR] %0t error response received!", $time);
    endtask

    function void post_randomize();
      string s;
      s = {s, "AFTER RANDOMIZATION \n"};
      s = {s, "=======================================\n"};
      s = {s, "fmt_config_sequence object content is as below: \n"};
      s = {s, super.sprint()};
      s = {s, "=======================================\n"};
      `uvm_info(get_type_name(), s, UVM_HIGH)
    endfunction
  endclass: fmt_config_sequence

  // formatter monitor
  class fmt_monitor extends uvm_monitor;
    local string name;
    local virtual fmt_intf intf;
    uvm_blocking_put_port #(fmt_trans) mon_bp_port;

    `uvm_component_utils(fmt_monitor)

    function new(string name="fmt_monitor", uvm_component parent);
      super.new(name, parent);
      mon_bp_port = new("mon_bp_port", this);
    endfunction

    function void set_interface(virtual fmt_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction

    task run_phase(uvm_phase phase);
      this.mon_trans();
    endtask

    task mon_trans();
      fmt_trans m;
      string s;
      forever begin
        @(posedge intf.mon_ck.fmt_start);
        m = new();
        m.length = intf.mon_ck.fmt_length;
        m.ch_id = intf.mon_ck.fmt_chid;
        m.data = new[m.length];
        foreach(m.data[i]) begin
          @(posedge intf.clk);
          m.data[i] = intf.mon_ck.fmt_data;
        end
        mon_bp_port.put(m);
        s = $sformatf("=======================================\n");
        s = {s, $sformatf("%0t %s monitored a packet: \n", $time, this.m_name)};
        s = {s, $sformatf("length = %0d: \n", m.length)};
        s = {s, $sformatf("chid = %0d: \n", m.ch_id)};
        foreach(m.data[i]) s = {s, $sformatf("data[%0d] = %8x \n", i, m.data[i])};
        s = {s, $sformatf("=======================================\n")};
        `uvm_info(get_type_name(), s, UVM_HIGH)
      end
    endtask
  endclass: fmt_monitor

  // formatter agent
  class fmt_agent extends uvm_agent;
    fmt_driver driver;
    fmt_monitor monitor;
    fmt_sequencer sequencer;
    local virtual fmt_intf vif;

    `uvm_component_utils(fmt_agent)

    function new(string name = "chnl_agent", uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      driver = fmt_driver::type_id::create("driver", this);
      monitor = fmt_monitor::type_id::create("monitor", this);
      sequencer = fmt_sequencer::type_id::create("sequencer", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

    function void set_interface(virtual fmt_intf vif);
      this.vif = vif;
      driver.set_interface(vif);
      monitor.set_interface(vif);
    endfunction
  endclass

endpackage
