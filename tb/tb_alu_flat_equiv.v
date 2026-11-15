// tb_alu_flat_equiv.v — proves alu_flat.v behaves exactly like alu.v on all 1,048,576 inputs,
// so the Stage 7 hardware comparison is apples to apples.
`timescale 1ns/1ps
module tb_alu_flat_equiv;
    reg  [7:0] a, b;  reg [3:0] op;
    wire [7:0] r1, r2;  wire c1, z1, n1, v1, c2, z2, n2, v2;
    alu      u1 (.a(a), .b(b), .op(op), .result(r1), .c(c1), .z(z1), .n(n1), .v(v1));
    alu_flat u2 (.a(a), .b(b), .op(op), .result(r2), .c(c2), .z(z2), .n(n2), .v(v2));
    integer i, errors = 0;
    initial begin
        for (i = 0; i < (1 << 20); i = i + 1) begin
            {op, a, b} = i;  #1;
            if ({r1, c1, z1, n1, v1} !== {r2, c2, z2, n2, v2}) begin
                errors = errors + 1;
                if (errors <= 5) $display("DIFF op=%h a=%h b=%h : shared %h %b%b%b%b  flat %h %b%b%b%b",
                                          op, a, b, r1, c1, z1, n1, v1, r2, c2, z2, n2, v2);
            end
        end
        $display("alu vs alu_flat: %0d inputs, %0d differences -> %s", i, errors, errors ? "FAIL" : "PASS");
        $finish;
    end
endmodule
