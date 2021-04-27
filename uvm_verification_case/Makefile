#############################
# User variables
#############################
all:clean comp elab run

TB       = tb
SEED     = 1
TESTNAME ?= mcdf_data_consistence_basic_test
DFILES   = ../mcdf/{arbiter.v,slave_fifo.v,reg.v,formater.v,mcdf.v}
VFILES  += arb_pkg.sv chnl_pkg.sv fmt_pkg.sv reg_pkg.sv mcdf_rgm_pkg.sv mcdf_pkg.sv $(TB).sv 


#############################
# Environment variables
#############################
VCOMP                = vlogan -full64 -ntb_opts uvm-1.1 -sverilog -timescale=1ps/1ps -nc -l comp.log +incdir+../mcdf
ELAB                 = vcs -full64 -ntb_opts uvm-1.1 -debug_all -l elab.log -sim_res=1ps -cm line+tgl+branch -cm_hier cm.cfg\
											-cpp g++-4.8 -cc gcc-4.8 -LDFLAGS -Wl,--no-as-needed
RUN                  = ./$(TB).simv -l run.log -sml -cm line+tgl+branch -cm_name $(TB)_$(SEED) +ntb_random_seed=$(SEED) +UVM_TESTNAME=$(TESTNAME)

comp:
	$(VCOMP) 
	$(VCOMP) $(DFILES) $(VFILES)

elab: comp
	$(ELAB) -top $(TB) -o $(TB).simv

run:
	$(RUN) 

rung:
	$(RUN) -gui

editcov:
	urg -full64 -format both -dir $(TB).simv.vdb 
	dve -cov -dir $(TB).simv.vdb

# option for exlucde file given to generate coverage report 
# if there is such a coverage exclusion file
# urg -dir ... -elfile filename.el
viewcov:
	urg -full64 -format both -dir $(TB).simv.vdb 
	firefox urgReport/dashboard.html

clean:
	rm -rf AN.DB DVEfiles csrc *.simv *.simv.daidir *.simv.vdb ucli.key
	rm -rf *.log* *.vpd *.h urgReport

