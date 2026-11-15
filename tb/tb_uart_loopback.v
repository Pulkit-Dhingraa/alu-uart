// tb_uart_loopback.v — our TX drives our RX through the synchroniser.
// Sends all 256 byte values back-to-back and checks every one comes out unchanged.
// Also measures: tick16 period, bit width on the wire, and frame length.
`timescale 1ns/1ps
module tb_uart_loopback;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;                 // 100 MHz

    wire tick16, txd, tx_busy, rxd_s, rx_valid, frame_err;
    wire [7:0] rx_data;
    reg  tx_start = 0;
    reg  [7:0] tx_data = 0;

    baud_gen #(.CLK_HZ(100_000_000), .BAUD(115_200)) u_bg (clk, rst_n, tick16);
    uart_tx u_tx (clk, rst_n, tick16, tx_start, tx_data, txd, tx_busy);
    sync2   u_sy (clk, rst_n, txd, rxd_s);
    uart_rx u_rx (clk, rst_n, tick16, rxd_s, rx_data, rx_valid, frame_err);

    // ---------- measurements ----------
    integer cyc = 0;  always @(posedge clk) cyc = cyc + 1;
    integer last_tick = -1, tick_period = 0;
    always @(posedge clk) if (tick16) begin
        if (last_tick >= 0) tick_period = cyc - last_tick;
        last_tick = cyc;
    end
    // shortest high/low run on txd while busy = one bit width (after the first byte)
    integer last_edge = 0, min_run = 1 << 30; reg txd_q = 1;
    always @(posedge clk) begin
        if (rst_n && txd_q !== 1'bx && txd !== txd_q) begin   // real edges only
            if (last_edge > 0 && (cyc - last_edge) < min_run) min_run = cyc - last_edge;
            last_edge = cyc;
        end
        txd_q <= txd;
    end
    integer frame_start = 0, frame_len = 0;

    // ---------- checker ----------
    integer expected = 0, errors = 0, got = 0;
    always @(posedge clk) begin
        if (rx_valid) begin
            if (rx_data !== expected[7:0]) begin
                errors = errors + 1;
                $display("MISMATCH: sent %02h got %02h", expected[7:0], rx_data);
            end
            expected = expected + 1; got = got + 1;
        end
        if (frame_err) begin errors = errors + 1; $display("FRAME_ERR at byte %0d", expected); end
    end

    integer i;
    initial begin
        repeat (5) @(posedge clk); rst_n = 1;
        for (i = 0; i < 256; i = i + 1) begin
            @(posedge clk); while (tx_busy) @(posedge clk);
            if (i == 1) frame_len = cyc - frame_start;
            if (i == 0) frame_start = cyc;
            tx_data <= i[7:0]; tx_start <= 1;
            @(posedge clk); tx_start <= 0;
        end
        @(posedge clk);                       // let tx_busy rise first (NBA race)
        while (tx_busy) @(posedge clk);
        repeat (2000) @(posedge clk);

        $display("------------------------------------------------");
        $display("tick16 period      : %0d clocks  (DIVISOR)", tick_period);
        $display("one bit on wire    : %0d clocks = %0d ns", min_run, min_run*10);
        $display("one frame (10 bits): %0d clocks = %0.2f us", frame_len, frame_len*0.01);
        $display("bytes received     : %0d / 256", got);
        $display("errors             : %0d", errors);
        $display("RESULT             : %s", (errors == 0 && got == 256) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
