// tb_baud_sweep.v — how far can the PC's baud rate drift before our RX breaks?
//
// A behavioural "PC" transmitter sends N random bytes BACK-TO-BACK (worst case: no idle
// gap after the stop bit) at  tx_baud = rx_baud_actual * (1 + m).
// Our real uart_rx (via sync2) receives them. PASS = every byte correct, no frame errors.
//
// Run:  vvp sim +M100=<mismatch in hundredths of a percent>  e.g. +M100=-450 -> -4.50 %
//   m > 0 : PC faster than us (its bits are shorter)
//   m < 0 : PC slower than us (its bits are longer)
`timescale 1ns/1ps
module tb_baud_sweep;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire tick16, rxd_s, rx_valid, frame_err;
    wire [7:0] rx_data;
    reg  line = 1'b1;                       // the wire from the PC

    baud_gen #(.CLK_HZ(100_000_000), .BAUD(115_200)) u_bg (clk, rst_n, tick16);
    sync2   u_sy (clk, rst_n, line, rxd_s);
    uart_rx u_rx (clk, rst_n, tick16, rxd_s, rx_data, rx_valid, frame_err);

    localparam integer N = 300;
    reg [7:0] sent [0:N-1];
    integer m100, seed, k, b, nrx = 0, bad = 0, ferr = 0;
    real rx_baud, tx_baud, Tbit;

    always @(posedge clk) begin
        if (rx_valid) begin
            if (nrx >= N || rx_data !== sent[nrx]) bad = bad + 1;
            nrx = nrx + 1;
        end
        if (frame_err) ferr = ferr + 1;
    end

    initial begin
        if (!$value$plusargs("M100=%d", m100)) m100 = 0;
        seed    = 12345 + m100;
        rx_baud = 100.0e6 / (54.0 * 16.0);                 // 115740.74 (our actual rate)
        tx_baud = rx_baud * (1.0 + m100 / 10000.0);
        Tbit    = 1.0e9 / tx_baud;                          // ns, not a multiple of 10 ns
        for (k = 0; k < N; k = k + 1) sent[k] = $random(seed);
        sent[0] = 8'h00; sent[1] = 8'hFF; sent[2] = 8'h55; sent[3] = 8'hAA; sent[4] = 8'hA5;

        repeat (5) @(posedge clk); rst_n = 1;
        #(1000.0 + ($random(seed) & 1023));                 // random starting phase
        for (k = 0; k < N; k = k + 1) begin
            line = 1'b0;               #(Tbit);             // start
            for (b = 0; b < 8; b = b + 1) begin
                line = sent[k][b];     #(Tbit);             // d0..d7, LSB first
            end
            line = 1'b1;               #(Tbit);             // stop, then next start at once
        end
        #(Tbit * 20);
        $display("m100=%0d  rx=%0d/%0d  bad=%0d  frame_err=%0d  %s",
                 m100, nrx, N, bad, ferr,
                 (nrx == N && bad == 0 && ferr == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
