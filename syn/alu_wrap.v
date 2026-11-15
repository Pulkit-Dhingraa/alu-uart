// alu_wrap.v — puts flip-flops on both sides of the ALU so Vivado can time it on its own.
//
//   a_in,b_in,op_in ─► [FF] ─► ALU (combinational) ─► [FF] ─► outputs
//
// The only register-to-register path goes THROUGH the ALU, so:
//   ALU delay ≈ data-path delay of the worst path,   Fmax(ALU) = 1 / (T - WNS)
// FLAT = 0 -> alu.v (shared adder)      FLAT = 1 -> alu_flat.v (one adder per op)
module alu_wrap #(
    parameter FLAT = 0
)(
    input  wire       clk,
    input  wire [7:0] a_in,
    input  wire [7:0] b_in,
    input  wire [3:0] op_in,
    output reg  [7:0] result_q,
    output reg  [3:0] flags_q          // {v, n, z, c}
);
    reg  [7:0] a_q, b_q;
    reg  [3:0] op_q;
    wire [7:0] result;
    wire       c, z, n, v;

    always @(posedge clk) begin
        a_q <= a_in;  b_q <= b_in;  op_q <= op_in;
        result_q <= result;
        flags_q  <= {v, n, z, c};
    end

    generate
        if (FLAT) begin : g_flat
            alu_flat u_alu (.a(a_q), .b(b_q), .op(op_q), .result(result), .c(c), .z(z), .n(n), .v(v));
        end else begin : g_shared
            alu      u_alu (.a(a_q), .b(b_q), .op(op_q), .result(result), .c(c), .z(z), .n(n), .v(v));
        end
    endgenerate
endmodule
