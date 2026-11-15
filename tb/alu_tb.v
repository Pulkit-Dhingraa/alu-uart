// ============================================================
// tb_alu.v  -  exhaustive testbench for alu.v
//
// Idea: write the ALU a SECOND time, in a completely different style
// (plain integer maths, one-bit-at-a-time loops) = the "reference model".
// Then try every A (256) x every B (256) x every op (16) = 1,048,576
// cases and check that the real ALU and the reference agree on
// result, C, Z, N and V.
// ============================================================
`timescale 1ns/1ps
module tb_alu;

    reg  [7:0] a, b;
    reg  [3:0] op;
    wire [7:0] result;
    wire       c, z, n, v;

    alu dut (.a(a), .b(b), .op(op), .result(result), .c(c), .z(z), .n(n), .v(v));

    // ---------------- reference model outputs ----------------
    reg  [7:0] exp_r;
    reg        exp_c, exp_v, exp_z, exp_n;

    integer sa, sb, s;           // signed versions of A, B (-128..127)
    integer i;
    reg [7:0] t;
    reg       out_bit;

    // Turn an 8-bit pattern into a signed number: 0x80..0xFF -> -128..-1
    function integer to_signed(input [7:0] x);
        to_signed = (x > 127) ? x - 256 : x;
    endfunction

    task reference;
        begin
            sa = to_signed(a);  sb = to_signed(b);
            exp_r = 0;  exp_c = 0;  exp_v = 0;
            case (op)
              0:  begin exp_r = a + b;  exp_c = (a + b) > 255;  s = sa + sb;  exp_v = (s > 127) || (s < -128); end // ADD
              1:  begin exp_r = a - b;  exp_c = (a < b);        s = sa - sb;  exp_v = (s > 127) || (s < -128); end // SUB
              2:  begin exp_r = a + 1;  exp_c = (a == 255);  exp_v = (a == 127); end                              // INC
              3:  begin exp_r = a - 1;  exp_c = (a == 0);    exp_v = (a == 128); end                              // DEC
              4:  exp_r = a & b;
              5:  exp_r = a | b;
              6:  exp_r = a ^ b;
              7:  exp_r = ~a;
              8:  begin t = a; out_bit = 0;                    // SLL: shift left one bit at a time, B times
                        for (i = 0; i < b; i = i + 1) begin out_bit = t[7]; t = {t[6:0], 1'b0}; end
                        exp_r = t; exp_c = out_bit; end
              9:  begin t = a; out_bit = 0;                    // SRL
                        for (i = 0; i < b; i = i + 1) begin out_bit = t[0]; t = {1'b0, t[7:1]}; end
                        exp_r = t; exp_c = out_bit; end
              10: begin t = a; out_bit = 0;                    // SRA: refill with the sign bit
                        for (i = 0; i < b; i = i + 1) begin out_bit = t[0]; t = {t[7], t[7:1]}; end
                        exp_r = t; exp_c = out_bit; end
              11: begin t = a; out_bit = 0;                    // ROL: B times, the bit leaving bit 7 re-enters bit 0
                        for (i = 0; i < b; i = i + 1) begin out_bit = t[7]; t = {t[6:0], t[7]}; end
                        exp_r = t; exp_c = out_bit; end
              12: begin exp_r = 0 - a;  exp_c = (a != 0);  exp_v = (a == 128); end                                // NEG
              13: begin exp_r = (sa < sb) ? 1 : 0;  exp_c = (a < b); end                                          // SLT
              14: begin exp_r = (a  < b ) ? 1 : 0;  exp_c = (a < b); end                                          // SLTU
              15: begin t = a; out_bit = 0;                    // ROR
                        for (i = 0; i < b; i = i + 1) begin out_bit = t[0]; t = {t[0], t[7:1]}; end
                        exp_r = t; exp_c = out_bit; end
            endcase
            // Z and N computed HERE, right after exp_r, so they are never stale
            exp_z = (exp_r == 8'h00);
            exp_n = exp_r[7];
        end
    endtask

    // ---------------- a few hand-picked examples, printed ----------------
    task show(input [3:0] o, input [7:0] x, input [7:0] y);
        begin
            op = o; a = x; b = y; #1;
            $display("  op=%h  A=%h  B=%h  ->  result=%h   C=%b Z=%b N=%b V=%b", op, a, b, result, c, z, n, v);
        end
    endtask

    integer ia, ib, iop;
    integer checked, errors;
    integer op_err [0:15];

    initial begin
        $display("---- hand-picked examples ----");
        show(4'h1, 8'h05, 8'h03);   // SUB 5-3          = 02, no borrow
        show(4'h1, 8'h03, 8'h05);   // SUB 3-5          = FE (-2), borrow
        show(4'h0, 8'h7F, 8'h01);   // ADD 127+1        = 80, V=1 (signed overflow)
        show(4'h0, 8'hFF, 8'h01);   // ADD 255+1        = 00, C=1, Z=1
        show(4'hD, 8'h80, 8'h01);   // SLT  -128 < 1 ?  = 1
        show(4'hE, 8'h80, 8'h01);   // SLTU  128 < 1 ?  = 0
        show(4'h8, 8'h81, 8'h01);   // SLL 1000_0001 << 1 = 02, C=1
        show(4'hA, 8'h80, 8'h09);   // SRA by 9         = FF (sign fill)

        $display("---- exhaustive run ----");
        checked = 0; errors = 0;
        for (iop = 0; iop < 16; iop = iop + 1) op_err[iop] = 0;

        for (iop = 0; iop < 16; iop = iop + 1)
          for (ia = 0; ia < 256; ia = ia + 1)
            for (ib = 0; ib < 256; ib = ib + 1) begin
                op = iop; a = ia; b = ib;
                #1;                                   // let the combinational logic settle
                reference;
                checked = checked + 1;
                if ({result, c, z, n, v} !== {exp_r, exp_c, exp_z, exp_n, exp_v}) begin
                    errors = errors + 1;
                    op_err[iop] = op_err[iop] + 1;
                    if (errors <= 10)
                        $display("MISMATCH op=%h A=%h B=%h : got %h C%b Z%b N%b V%b, expected %h C%b Z%b N%b V%b",
                                 op, a, b, result, c, z, n, v, exp_r, exp_c, exp_z, exp_n, exp_v);
                end
            end

        for (iop = 0; iop < 16; iop = iop + 1)
            if (op_err[iop] != 0) $display("  op %h : %0d mismatches", iop, op_err[iop]);

        $display("Checked %0d vectors, %0d mismatches  ->  %s",
                 checked, errors, (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end

endmodule