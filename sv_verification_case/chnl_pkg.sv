package chnl_pkg;
//发送Chnl的数据
  class chnl_trans;
    rand bit[31:0] data[];
    rand int ch_id;
    rand int pkt_id;
    rand int data_nidles;//相邻数据的间隔
    rand int pkt_nidles;//相邻数据包的间隔
    bit rsp;
    constraint cstr{
      soft data.size inside {[4:32]};
	  //动态数组的约束
      foreach(data[i]) data[i] == 'hC000 _0000 + (this.ch_id<<24) + (this.pkt_id<<8) + i;
      //soft表示软约束
	  soft ch_id == 0;
      soft pkt_id == 0;
      soft data_nidles inside {[0:2]};
      soft pkt_nidles inside {[1:10]};
    };

    function chnl_trans clone();
      chnl_trans c = new();
      c.data = this.data;
      c.ch_id = this.ch_id;
      c.pkt_id = this.pkt_id;
      c.data_nidles = this.data_nidles;
      c.pkt_nidles = this.pkt_nidles;
      c.rsp = this.rsp;
      return c;
    endfunction

    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("chnl_trans object content is as below: \n")};
      foreach(data[i]) s = {s, $sformatf("data[%0d] = %8x \n", i, this.data[i])};
      s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};
      s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};
      s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)};
      s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)};
      s = {s, $sformatf("rsp = %0d: \n", this.rsp)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction
  endclass: chnl_trans
  
  class chnl_driver;
    local string name;
    local virtual chnl_intf intf;
    mailbox #(chnl_trans) req_mb;
    mailbox #(chnl_trans) rsp_mb;
  
    function new(string name = "chnl_driver");
      this.name = name;
    endfunction
  
    function void set_interface(virtual chnl_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction

    task run();
      fork
       this.do_drive();
       this.do_reset();
      join
    endtask

    task do_reset();
      forever begin
        @(negedge intf.rstn);
        intf.ch_valid <= 0;
        intf.ch_data <= 0;
      end
    endtask

    task do_drive();
      chnl_trans req, rsp;//产生两个空句柄
      @(posedge intf.rstn);
      forever begin
        this.req_mb.get(req);
        this.chnl_write(req);
        rsp = req.clone();
        rsp.rsp = 1;
        this.rsp_mb.put(rsp);
      end
    endtask
  
    task chnl_write(input chnl_trans t);
      foreach(t.data[i]) begin
        @(posedge intf.clk);
        intf.drv_ck.ch_valid <= 1;
        intf.drv_ck.ch_data <= t.data[i];
        @(negedge intf.clk);
        wait(intf.ch_ready === 'b1);
        $display("%0t channel driver [%s] sent data %x", $time, name, t.data[i]);
        repeat(t.data_nidles) chnl_idle();
      end
      repeat(t.pkt_nidles) chnl_idle();
    endtask
    
    task chnl_idle();
      @(posedge intf.clk);
      intf.drv_ck.ch_valid <= 0;
      intf.drv_ck.ch_data <= 0;
    endtask
  endclass: chnl_driver
  
  class chnl_generator;
    rand int pkt_id = 0;
    rand int ch_id = -1;
    rand int data_nidles = -1;
    rand int pkt_nidles = -1;
    rand int data_size = -1;
    rand int ntrans = 10;

    mailbox #(chnl_trans) req_mb;
    mailbox #(chnl_trans) rsp_mb;

    constraint cstr{
      soft ch_id == -1;
      soft pkt_id == 0;
      soft data_size == -1;
      soft data_nidles == -1;
      soft pkt_nidles == -1;
      soft ntrans == 10;
    }

    function new();
      this.req_mb = new();
      this.rsp_mb = new();
    endfunction

    task start();
      repeat(ntrans) send_trans();
    endtask

    task send_trans();
      chnl_trans req, rsp;
      req = new();     //chnl_generator.ch_id     req.ch_id
      assert(req.randomize with {local::ch_id >= 0 -> ch_id == local::ch_id; 
                                 local::pkt_id >= 0 -> pkt_id == local::pkt_id;
                                 local::data_nidles >= 0 -> data_nidles == local::data_nidles;
                                 local::pkt_nidles >= 0 -> pkt_nidles == local::pkt_nidles;
                                 local::data_size >0 -> data.size() == local::data_size; 
                               })
        else $fatal("[RNDFAIL] channel packet randomization failure!");
      this.pkt_id++;
      $display(req.sprint());
	  //握手操作
      this.req_mb.put(req);
      this.rsp_mb.get(rsp);
      $display(rsp.sprint());
      assert(rsp.rsp)
        else $error("[RSPERR] %0t error response received!", $time);
    endtask

    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("chnl_generator object content is as below: \n")};
      s = {s, $sformatf("ntrans = %0d: \n", this.ntrans)};
      s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};
      s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};
      s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)};
      s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)};
      s = {s, $sformatf("data_size = %0d: \n", this.data_size)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction

    function void post_randomize();
      string s;
      s = {"AFTER RANDOMIZATION \n", this.sprint()};
      $display(s);
    endfunction
  endclass: chnl_generator

  typedef struct packed {
    bit[31:0] data;
    bit[1:0] id;
  } mon_data_t;

  class chnl_monitor;
    local string name;
    local virtual chnl_intf intf;
    mailbox #(mon_data_t) mon_mb;
    function new(string name="chnl_monitor");
      this.name = name;
    endfunction
    function void set_interface(virtual chnl_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction
    task run();
      this.mon_trans();
    endtask

    task mon_trans();
      mon_data_t m;
      forever begin
        @(posedge intf.clk iff (intf.mon_ck.ch_valid==='b1 && intf.mon_ck.ch_ready==='b1));
        m.data = intf.mon_ck.ch_data;
        mon_mb.put(m);
        $display("%0t %s monitored channle data %8x", $time, this.name, m.data);
      end
    endtask
  endclass
  
  class chnl_agent;
    local string name;
    chnl_driver driver;
    chnl_monitor monitor;
    local virtual chnl_intf vif;
    function new(string name = "chnl_agent");
      this.name = name;
      this.driver = new({name, ".driver"});
      this.monitor = new({name, ".monitor"});
    endfunction

    function void set_interface(virtual chnl_intf vif);
      this.vif = vif;
      driver.set_interface(vif);
      monitor.set_interface(vif);
    endfunction
    task run();
      fork
        driver.run();
        monitor.run();
      join
    endtask
  endclass: chnl_agent

endpackage

