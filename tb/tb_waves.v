// tb_waves.v — small testbench used ONLY to produce the waveform pictures in docs/img.
// It sends one request [A5 05 03 00] (ADD 5 + 3) at exactly 115200 baud, waits for the
// 2-byte reply, and dumps the interesting signals to build/waves.vcd.
// The pictures are drawn from that dump by scripts/plot_waves.py.
`timescale 1ns/1ps
module tb_waves;
    reg clk = 0;  always #5 clk = ~clk;          // 100 MHz
    reg resetn = 0;
    reg line   = 1'b1;
    wire txd;

    alu_uart_top dut (.clk(clk), .cpu_resetn(resetn), .uart_rxd(line), .uart_txd(txd));

    localparam real T_PC = 1.0e9 / 115200.0;     // PC bit time = 8680.56 ns

    // 1 exactly on the clocks where uart_rx reads the line (middle of each bit)
    wire rx_sample = dut.u_rx.tick16 &&
                     ((dut.u_rx.state == 2'd1 && dut.u_rx.tick_cnt == 4'd7) ||
                      (dut.u_rx.state >= 2'd2 && dut.u_rx.tick_cnt == 4'd15));

    task pc_byte(input [7:0] d);
        integer i;
        begin
            line = 1'b0;                 #(T_PC);
            for (i = 0; i < 8; i = i + 1) begin line = d[i]; #(T_PC); end
            line = 1'b1;                 #(T_PC);
        end
    endtask

    initial begin
        $dumpfile("build/waves.vcd");
        $dumpvars(0, clk, line, txd, rx_sample);
        $dumpvars(0, dut.tick16, dut.rx_valid, dut.rx_data, dut.tx_start, dut.tx_busy, dut.tx_data);
        $dumpvars(0, dut.u_fsm.rx_state, dut.u_fsm.tx_state, dut.u_fsm.calc,
                     dut.u_fsm.a, dut.u_fsm.b, dut.u_fsm.op_byte, dut.alu_result);
        repeat (10) @(posedge clk);  resetn = 1;
        repeat (10) @(posedge clk);
        #(2 * T_PC);
        pc_byte(8'hA5); pc_byte(8'h05); pc_byte(8'h03); pc_byte(8'h00);
        #(25 * T_PC);
        $finish;
    end
endmodule
