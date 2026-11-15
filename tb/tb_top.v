// tb_top.v — end-to-end test of alu_uart_top, through the pins only.
//
//   "PC" task  ──bits on uart_rxd──►  DUT  ──bits on uart_txd──►  "listener" (decodes bytes)
//
// The PC runs at EXACTLY 115200 baud (bit = 8680.6 ns); our design runs at 115741 (+0.47 %),
// so the real-world rate mismatch is part of the test.
//
// For every packet the testbench pushes the reply it EXPECTS into a queue
// (computed with a reference copy of the ALU, already proven exhaustively in Stage 1).
// The listener pushes what it actually RECEIVES. At the end the two queues must match.
//
// Part 1: directed tests, one per feature / fault.   Part 2: N random packets back-to-back.
`timescale 1ns/1ps
module tb_top;
    // ---------------- clock, reset, DUT ----------------
    reg clk = 0;  always #5 clk = ~clk;          // 100 MHz
    reg resetn = 0;
    reg line   = 1'b1;                           // uart_rxd: idle high
    wire txd;

    alu_uart_top dut (.clk(clk), .cpu_resetn(resetn), .uart_rxd(line), .uart_txd(txd));

    localparam real T_PC  = 1.0e9 / 115200.0;    // PC bit time   = 8680.56 ns
    localparam real T_DUT = 8640.0;              // our bit time  = 864 clocks
    localparam integer N_RANDOM = 1000;

    // ---------------- reference ALU (for expected replies) ----------------
    reg  [7:0] ra = 0, rb = 0;  reg [3:0] rop = 0;
    wire [7:0] rr;  wire rc, rz, rn, rv;
    alu ref_alu (.a(ra), .b(rb), .op(rop), .result(rr), .c(rc), .z(rz), .n(rn), .v(rv));

    // ---------------- expected / received reply bytes ----------------
    reg  [7:0] exp_q [0:8191];   integer n_exp = 0;
    reg  [7:0] got_q [0:8191];   integer n_got = 0;
    real       got_t [0:8191];   // time each received byte started
    integer    n_checked = 0, mismatches = 0, stop_errs = 0;

    // ====================================================================
    // PC side: drive bits onto the wire
    // ====================================================================
    task pc_byte(input [7:0] d);                 // start, d0..d7 (LSB first), stop
        integer i;
        begin
            line = 1'b0;                 #(T_PC);
            for (i = 0; i < 8; i = i + 1) begin line = d[i]; #(T_PC); end
            line = 1'b1;                 #(T_PC);
        end
    endtask

    task pc_byte_bad_stop(input [7:0] d);        // stop bit pulled LOW at its middle -> frame error
        integer i;
        begin
            line = 1'b0;                 #(T_PC);
            for (i = 0; i < 8; i = i + 1) begin line = d[i]; #(T_PC); end
            line = 1'b0;                 #(0.75 * T_PC);   // still low when our RX samples at 9.5 bits
            line = 1'b1;                 #(0.25 * T_PC);
        end
    endtask

    task idle_bits(input integer n);  #(n * T_PC);  endtask

    // Work out the reply the design SHOULD send and queue it.
    // f = the sticky FRAME_ERR bit this reply should carry. Bit 5 is reserved and must be 0.
    task expect_reply(input [7:0] A, input [7:0] B, input [7:0] OP, input f);
        begin
            ra = A; rb = B; rop = OP[3:0];
            #1;                                          // let the reference ALU settle
            if (OP[7:4] != 4'h0) begin                   // BAD_OP: result 00, flags 0
                exp_q[n_exp] = 8'h00;  exp_q[n_exp+1] = {1'b0, f, 1'b0, 1'b1, 4'b0000};
            end else begin
                exp_q[n_exp] = rr;     exp_q[n_exp+1] = {1'b0, f, 1'b0, 1'b0, rv, rn, rz, rc};
            end
            n_exp = n_exp + 2;
        end
    endtask

    task packet(input [7:0] A, input [7:0] B, input [7:0] OP, input f);
        begin
            expect_reply(A, B, OP, f);
            pc_byte(8'hA5); pc_byte(A); pc_byte(B); pc_byte(OP);
        end
    endtask

    // ====================================================================
    // Listener: decode every byte the DUT sends on txd
    // ====================================================================
    reg [7:0] rx_byte;  integer k;  real t_start;
    always begin
        @(negedge txd);                              // start bit begins
        t_start = $realtime;
        #(T_DUT / 2);                                // middle of start bit
        for (k = 0; k < 8; k = k + 1) begin #(T_DUT); rx_byte[k] = txd; end
        #(T_DUT);                                    // middle of stop bit
        if (txd !== 1'b1) stop_errs = stop_errs + 1;
        got_q[n_got] = rx_byte;  got_t[n_got] = t_start;  n_got = n_got + 1;
    end

    // Wait for all expected replies, compare the new ones, and make sure no EXTRA reply comes.
    task check_replies(input [8*40-1:0] label);
        integer i, waited;
        begin
            waited = 0;
            while (n_got < n_exp && waited < 4000) begin #(1000); waited = waited + 1; end   // up to 4 ms
            #(30 * T_DUT);                           // 3 more frames: catch any extra byte
            if (n_got != n_exp) begin
                mismatches = mismatches + 1;
                $display("  %0s: expected %0d reply bytes so far, got %0d", label, n_exp, n_got);
            end
            for (i = n_checked; i < n_exp && i < n_got; i = i + 1)
                if (got_q[i] !== exp_q[i]) begin
                    mismatches = mismatches + 1;
                    if (mismatches <= 10)
                        $display("  MISMATCH byte %0d: got %h expected %h", i, got_q[i], exp_q[i]);
                end
            n_checked = n_exp;
        end
    endtask

    task show_last_reply(input [8*60-1:0] what);
        $display("%0s -> got [%h %h]  expected [%h %h]  %0s", what,
                 got_q[n_exp-2], got_q[n_exp-1], exp_q[n_exp-2], exp_q[n_exp-1],
                 (got_q[n_exp-2] === exp_q[n_exp-2] && got_q[n_exp-1] === exp_q[n_exp-1]) ? "OK" : "WRONG");
    endtask

    // ---------------- latency: last request byte received -> reply start bit ----------------
    real t_last_rxv = 0, latency = -1;
    always @(posedge clk) if (dut.rx_valid) t_last_rxv = $realtime;
    always @(negedge txd) if (latency < 0 && t_last_rxv > 0) latency = $realtime - t_last_rxv;

    // ====================================================================
    // The test sequence
    // ====================================================================
    integer p, n_bad = 0, first_rand_byte;
    reg [7:0] ra_, rb_, rop_;
    integer seed = 2026;

    initial begin
        repeat (10) @(posedge clk);
        resetn = 1;
        repeat (10) @(posedge clk);
        idle_bits(5);

        $display("================ PART 1: directed tests ================");

        // T1: plain ADD
        packet(8'h05, 8'h03, 8'h00, 0);                   check_replies("T1");
        show_last_reply("T1 ADD      PC sends [A5 05 03 00]           ");
        idle_bits(5);

        // T2: signed overflow -> status = V,N = 0000_1100 = 0C
        packet(8'h7F, 8'h01, 8'h00, 0);                   check_replies("T2");
        show_last_reply("T2 ADD ovf  PC sends [A5 7F 01 00]           ");
        idle_bits(5);

        // T3: junk before the header is thrown away
        pc_byte(8'h33); pc_byte(8'h77);
        packet(8'h0A, 8'h03, 8'h01, 0);                   check_replies("T3");
        show_last_reply("T3 junk     PC sends [33 77 A5 0A 03 01]     ");
        idle_bits(5);

        // T4: BAD_OP (upper nibble of op is not 0)
        packet(8'h01, 8'h02, 8'h10, 0);                   check_replies("T4");
        show_last_reply("T4 BAD_OP   PC sends [A5 01 02 10]           ");
        idle_bits(5);

        // T5a: a pause of ~1.2 frames mid-packet is allowed (no timeout)
        pc_byte(8'hA5); pc_byte(8'h06); idle_bits(12);
        expect_reply(8'h06, 8'h07, 8'h00, 0); pc_byte(8'h07); pc_byte(8'h00);
        check_replies("T5a");
        show_last_reply("T5a pause   PC sends [A5 06] wait [07 00]    ");
        idle_bits(5);

        // T5b: PC stops mid-packet -> timeout, no reply; the next packet works
        pc_byte(8'hA5); pc_byte(8'h05); idle_bits(40);       // 4 frames of silence
        packet(8'h01, 8'h02, 8'h00, 0);                   check_replies("T5b");
        show_last_reply("T5b timeout PC sends [A5 05] ... [A5 01 02 00]");
        idle_bits(5);

        // T6: frame error mid-packet -> packet dropped, next reply carries FRAME_ERR (bit 6)
        pc_byte(8'hA5); pc_byte(8'h05); pc_byte_bad_stop(8'h03); idle_bits(5);
        packet(8'h01, 8'h01, 8'h00, 1);                   check_replies("T6");
        show_last_reply("T6 frame    PC sends [A5 05 03*] [A5 01 01 00]");
        packet(8'h01, 8'h01, 8'h00, 0);                   check_replies("T6b");
        show_last_reply("T6b cleared PC sends [A5 01 01 00]           ");
        idle_bits(5);

        // T7: a byte vanishes (op of packet 1 missing), packets back-to-back.
        //     The next A5 lands in the op slot -> BAD_OP; the leftover [01 01 00] is junk.
        exp_q[n_exp] = 8'h00; exp_q[n_exp+1] = 8'h10; n_exp = n_exp + 2;
        pc_byte(8'hA5); pc_byte(8'h05); pc_byte(8'h03);
        pc_byte(8'hA5); pc_byte(8'h01); pc_byte(8'h01); pc_byte(8'h00);
        check_replies("T7");
        show_last_reply("T7 lost op  PC sends [A5 05 03][A5 01 01 00] ");
        packet(8'h02, 8'h02, 8'h00, 0);                   check_replies("T7b");
        show_last_reply("T7b recover PC sends [A5 02 02 00]           ");
        idle_bits(5);

        // T8: no FIFO -> the next packet arrives WHILE the reply is still going out.
        //     Two packets with zero gap; the second A5 lands while [result] is on the wire.
        packet(8'h10, 8'h20, 8'h00, 0);
        packet(8'h30, 8'h40, 8'h01, 0);                      check_replies("T8");
        show_last_reply("T8 overlap  PC sends [A5 10 20 00][A5 30 40 01]");
        idle_bits(5);

        $display("Latency, last request byte received -> reply start bit: %0.0f ns (%0.0f clocks)",
                 latency, latency / 10.0);

        $display("================ PART 2: %0d random packets, back-to-back ================", N_RANDOM);
        first_rand_byte = n_exp;
        for (p = 0; p < N_RANDOM; p = p + 1) begin
            ra_ = $random(seed);  rb_ = $random(seed);  rop_ = $random(seed);
            if (($random(seed) & 15) != 0) rop_[7:4] = 4'h0;    // ~94 % legal ops, rest BAD_OP
            else if (rop_[7:4] == 0)       rop_[7:4] = 4'h8;
            if (rop_[7:4] != 0) n_bad = n_bad + 1;
            packet(ra_, rb_, rop_, 0);                    // no idle between packets
        end
        check_replies("random");

        $display("Random phase: %0d packets (%0d BAD_OP), reply rate measured = %0.1f ops/s",
                 N_RANDOM, n_bad,
                 (N_RANDOM - 1) * 1.0e9 / (got_t[n_exp - 2] - got_t[first_rand_byte]));

        $display("=========================================================");
        $display("Reply bytes expected %0d, received %0d, mismatches %0d, bad stop bits %0d",
                 n_exp, n_got, mismatches, stop_errs);
        $display("RESULT: %s", (mismatches == 0 && stop_errs == 0 && n_got == n_exp) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
