onerror {resume}

set incdir  ../include
set rtldir  ../rtl
set tbdir   ../testbench
set workdir ../work
#
vlib $workdir
#
vlog -work $workdir -incr -sv +incdir+$incdir+$rtldir $rtldir/*.sv
vlog -work $workdir -incr -sv +incdir+$incdir+$rtldir $rtldir/buffer/*.sv
vlog -work $workdir -incr -sv +incdir+$incdir+$rtldir $rtldir/biterr_cnt/*.sv
#
vlog -work $workdir -incr -sv +incdir+$incdir+$rtldir/ldpc_dvb $rtldir/ldpc_dvb/*.sv
vlog -work $workdir -incr -sv +incdir+$incdir+$rtldir/ldpc_dvb/enc $rtldir/ldpc_dvb/enc/*.sv
vlog -work $workdir -incr -sv +incdir+$incdir+$rtldir/ldpc_dvb/dec $rtldir/ldpc_dvb/dec/*.sv

vlog -work $workdir +initreg+0 -sv +incdir+$incdir+$tbdir/ldpc_dvb $tbdir/ldpc_dvb/bertest_x.sv

set seed [clock seconds]

vsim -sv_seed $seed bertest_x -lib $workdir
run -all
