#############################
# User variables
#############################
all:comp elab run

TB       = tb_ref
SEED     = 1
TESTNAME ?= mcdf_down_stream_low_bandwidth_test
DFILES   = ../mcdf/v0/{arbiter.v,slave_fifo.v,reg.v,formater.v,mcdf.v}
VFILES  += rpt_pkg.sv arb_pkg.sv chnl_pkg.sv fmt_pkg.sv reg_pkg.sv mcdf_pkg_ref.sv $(TB).sv

#code coverage command
CM = -cm line+cond+fsm+branch+tgl#设置覆盖率检测
CM_NAME = -cm_name $(TB)_$(SEED)_$(TESTNAME)#覆盖率名字
CM_DIR = -cm_dir ./$(TB).simv.vdb

#generate fsdb file 
FSDB = -fsdb +define+FSDB

#generate vdp file 
VDP = +vcs+vcdpluson

#############################
# Environment variables
#############################
VCOMP = vlogan -full64 -sverilog -timescale=1ps/1ps -nc -l comp.log +incdir+../mcdf/v0

ELAB = vcs -full64 -cpp g++-4.8 -cc gcc-4.8 -LDFLAGS -Wl,--no-as-needed\
			 -debug_all\
			 -l elab.log -sim_res=1ps\
			 $(CM) -cm_hier cm.cfg

RUN = ./$(TB).simv\
			$(CM) $(CM_NAME)\
			+ntb_random_seed=$(SEED)\
			+TESTNAME=$(TESTNAME)\
			-l run.log -sml

#start compile
comp:
	$(VCOMP) $(DFILES) $(VFILES)

elab: 
	$(ELAB) -top $(TB) -o $(TB).simv
#start simulation

run:
	$(RUN) 

rung:
	$(RUN) -gui

editcov:
	urg -full64 -format both -dir $(TB).simv.vdb 
	dve -full64 -cov -dir $(TB).simv.vdb

# option for exlucde file given to generate coverage report 
# if there is such a coverage exclusion file
# urg -dir ... -elfile filename.el
viewcov:
	urg -full64 -format both -dir $(TB).simv.vdb 
	firefox urgReport/dashboard.html

mergecov:
	urg -full64 -dir ./$(TB).simv.vdb -dbname mergedir/merged

clean:
	rm -rf AN.DB DVEfiles csrc *.simv *.simv.daidir *.simv.vdb ucli.key
	rm -rf *.log* *.vpd urgReport
