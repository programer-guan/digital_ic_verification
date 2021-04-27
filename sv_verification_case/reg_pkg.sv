`include "param_def.v"

package reg_pkg;
//发送寄存读写的数据
  class reg_trans;
    rand bit[7:0] addr;
    rand bit[1:0] cmd;
    rand bit[31:0] data;
    bit rsp;

    constraint cstr {
      soft cmd inside {`WRITE, `READ, `IDLE};
      soft addr inside {`SLV0_RW_ADDR, `SLV1_RW_ADDR, `SLV2_RW_ADDR, `SLV0_R_ADDR, `SLV1_R_ADDR, `SLV2_R_ADDR};
      addr[7:4]==0 && cmd==`WRITE -> soft data[31:6]==0;//若对读寄存器进行写操作
      soft addr[7:5]==0;
      addr[4]==1 -> soft cmd == `READ;//表示只读寄存器
    };
 
    function reg_trans clone();
      reg_trans c = new();
      c.addr = this.addr;
      c.cmd = this.cmd;
      c.data = this.data;
      c.rsp = this.rsp;
      return c;
    endfunction

    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("reg_trans object content is as below: \n")};
      s = {s, $sformatf("addr = %2x: \n", this.addr)};
      s = {s, $sformatf("cmd = %2b: \n", this.cmd)};
      s = {s, $sformatf("data = %8x: \n", this.data)};
      s = {s, $sformatf("rsp = %0d: \n", this.rsp)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction
  endclass
//发送激励
  class reg_driver;
    local string name;
    local virtual reg_intf intf;
    mailbox #(reg_trans) req_mb;
    mailbox #(reg_trans) rsp_mb;

    function new(string name = "reg_driver");
      this.name = name;
    endfunction
  
    function void set_interface(virtual reg_intf intf);
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
        intf.cmd_addr <= 0;
        intf.cmd <= `IDLE;
        intf.cmd_data_m2s <= 0;
      end
    endtask

    task do_drive();
      reg_trans req, rsp;
      @(posedge intf.rstn);
      forever begin
        this.req_mb.get(req);
        this.reg_write(req);
        rsp = req.clone();
        rsp.rsp = 1;
        this.rsp_mb.put(rsp);
      end
    endtask
 //读写操作时序设计
    task reg_write(reg_trans t);
      @(posedge intf.clk iff intf.rstn);
      case(t.cmd)
        `WRITE: begin 
                  intf.drv_ck.cmd_addr <= t.addr; 
                  intf.drv_ck.cmd <= t.cmd; 
                  intf.drv_ck.cmd_data_m2s <= t.data; 
                end
        `READ:  begin 
                  intf.drv_ck.cmd_addr <= t.addr; 
                  intf.drv_ck.cmd <= t.cmd; 
				  //注意：这里需要等待两个下降沿，因为读数据时数据在下一个下降沿生效
                  repeat(2) @(negedge intf.clk);
                  t.data = intf.cmd_data_s2m; 
                end
        `IDLE:  begin 
                  this.reg_idle(); 
                end
        default: $error("command %b is illegal", t.cmd);
      endcase
      $display("%0t reg driver [%s] sent addr %2x, cmd %2b, data %8x", $time, name, t.addr, t.cmd, t.data);
    endtask
    
    task reg_idle();
      @(posedge intf.clk);
      intf.drv_ck.cmd_addr <= 0;
      intf.drv_ck.cmd <= `IDLE;
      intf.drv_ck.cmd_data_m2s <= 0;
    endtask
  endclass

  class reg_generator;
    rand bit[7:0] addr = -1;
    rand bit[1:0] cmd = -1;
    rand bit[31:0] data = -1;

    mailbox #(reg_trans) req_mb;
    mailbox #(reg_trans) rsp_mb;

    reg_trans reg_req[$];

    constraint cstr{
      soft addr == -1;
      soft cmd == -1;
      soft data == -1;
    }

    function new();
      this.req_mb = new();
      this.rsp_mb = new();
    endfunction

    task start();
      send_trans();
    endtask

    // generate transaction and put into local mailbox
    task send_trans();
      reg_trans req, rsp;
      req = new();
      assert(req.randomize with {local::addr >= 0 -> addr == local::addr;
                                 local::cmd >= 0 -> cmd == local::cmd;
                                 local::data >= 0 -> data == local::data;
                               })
        else $fatal("[RNDFAIL] register packet randomization failure!");
      $display(req.sprint());
      this.req_mb.put(req);
      this.rsp_mb.get(rsp);
      $display(rsp.sprint());
      if(req.cmd == `READ) 
        this.data = rsp.data;
      assert(rsp.rsp)
        else $error("[RSPERR] %0t error response received!", $time);
    endtask

    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("reg_generator object content is as below: \n")};
      s = {s, $sformatf("addr = %2x: \n", this.addr)};
      s = {s, $sformatf("cmd = %2b: \n", this.cmd)};
      s = {s, $sformatf("data = %8x: \n", this.data)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction

    function void post_randomize();
      string s;
      s = {"AFTER RANDOMIZATION \n", this.sprint()};
      $display(s);
    endfunction
  endclass

  class reg_monitor;
    local string name;
    local virtual reg_intf intf;
    mailbox #(reg_trans) mon_mb;
    function new(string name="reg_monitor");
      this.name = name;
    endfunction 
    function void set_interface(virtual reg_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction
    task run();
      this.mon_trans();
    endtask

    task mon_trans();
      reg_trans m;
      forever begin
        @(posedge intf.clk iff (intf.rstn && intf.mon_ck.cmd != `IDLE));
        m = new();
        m.addr = intf.mon_ck.cmd_addr;
        m.cmd = intf.mon_ck.cmd;
        if(intf.mon_ck.cmd == `WRITE) begin
          m.data = intf.mon_ck.cmd_data_m2s;
        end
        else if(intf.mon_ck.cmd == `READ) begin
          @(posedge intf.clk);
          m.data = intf.mon_ck.cmd_data_s2m;
        end
        mon_mb.put(m);
        $display("%0t %s monitored addr %2x, cmd %2b, data %8x", $time, this.name, m.addr, m.cmd, m.data);
      end
    endtask
  endclass

  class reg_agent;
    local string name;
    reg_driver driver;
    reg_monitor monitor;
    local virtual reg_intf vif;
    function new(string name = "reg_agent");
      this.name = name;
      this.driver = new({name, ".driver"});
      this.monitor = new({name, ".monitor"});
    endfunction

    function void set_interface(virtual reg_intf vif);
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
  endclass

endpackage
