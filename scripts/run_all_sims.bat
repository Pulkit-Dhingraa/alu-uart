@echo off
REM run_all_sims.bat — every simulation in the project, in order (Windows).
REM Run from the repository root:  scripts\run_all_sims.bat
REM Needs iverilog and vvp on the PATH.
if not exist build mkdir build

echo ===== 1. ALU exhaustive =====
iverilog -g2012 -o build/sim_alu.vvp tb/alu_tb.v rtl/alu.v || goto :fail
vvp -n build/sim_alu.vvp

echo ===== 2. Flat ALU equals shared ALU =====
iverilog -g2012 -o build/sim_eq.vvp tb/tb_alu_flat_equiv.v rtl/alu.v syn/alu_flat.v || goto :fail
vvp -n build/sim_eq.vvp

echo ===== 3. UART loopback =====
iverilog -g2012 -o build/sim_lb.vvp tb/tb_uart_loopback.v rtl/baud_gen.v rtl/uart_tx.v rtl/uart_rx.v rtl/sync2.v || goto :fail
vvp -n build/sim_lb.vvp

echo ===== 4. Baud edges: should PASS at -525 and +455, FAIL at -530 and +460 =====
iverilog -g2012 -o build/sim_sw.vvp tb/tb_baud_sweep.v rtl/baud_gen.v rtl/uart_rx.v rtl/sync2.v || goto :fail
for %%m in (-530 -525 455 460) do vvp -n build/sim_sw.vvp +M100=%%m | findstr m100

echo ===== 5. End-to-end, through the pins =====
iverilog -g2012 -o build/sim_top.vvp tb/tb_top.v rtl/alu_uart_top.v rtl/alu.v rtl/fsm.v rtl/baud_gen.v rtl/sync2.v rtl/uart_rx.v rtl/uart_tx.v || goto :fail
vvp -n build/sim_top.vvp
goto :eof

:fail
echo Compile failed.
