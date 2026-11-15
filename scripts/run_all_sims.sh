#!/usr/bin/env bash
# Runs every simulation in the project, in order. Needs iverilog and vvp on the PATH.
# Usage (from the repository root):  bash scripts/run_all_sims.sh
set -e
cd "$(dirname "$0")/.."
mkdir -p build sim_logs
R=rtl; T=tb; S=syn

echo "===== 1. ALU exhaustive ====="
iverilog -g2012 -o build/sim_alu.vvp $T/alu_tb.v $R/alu.v
vvp -n build/sim_alu.vvp | tee sim_logs/1_alu_exhaustive.log

echo "===== 2. Flat ALU equals shared ALU ====="
iverilog -g2012 -o build/sim_eq.vvp $T/tb_alu_flat_equiv.v $R/alu.v $S/alu_flat.v
vvp -n build/sim_eq.vvp | tee sim_logs/2_alu_flat_equiv.log

echo "===== 3. UART loopback ====="
iverilog -g2012 -o build/sim_lb.vvp $T/tb_uart_loopback.v $R/baud_gen.v $R/uart_tx.v $R/uart_rx.v $R/sync2.v
vvp -n build/sim_lb.vvp | tee sim_logs/3_uart_loopback.log

echo "===== 4. Baud edges: expect PASS at -525 and +455, FAIL at -530 and +460 ====="
iverilog -g2012 -o build/sim_sw.vvp $T/tb_baud_sweep.v $R/baud_gen.v $R/uart_rx.v $R/sync2.v
: > sim_logs/4_baud_sweep.log
for m in -530 -525 -500 -400 -200 0 200 400 455 460; do
    vvp -n build/sim_sw.vvp +M100=$m | grep m100 | tee -a sim_logs/4_baud_sweep.log
done

echo "===== 5. End-to-end, through the pins ====="
iverilog -g2012 -o build/sim_top.vvp $T/tb_top.v $R/alu_uart_top.v $R/alu.v $R/fsm.v $R/baud_gen.v $R/sync2.v $R/uart_rx.v $R/uart_tx.v
vvp -n build/sim_top.vvp | tee sim_logs/5_top_end_to_end.log
