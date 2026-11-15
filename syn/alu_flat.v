// alu_flat.v — SAME behaviour as alu.v, written the "flat" way:
// every arithmetic op gets its OWN adder/subtractor/comparator.
// Only used for the Stage 7 hardware comparison (shared adder vs flat). Not in the top level.
module alu_flat (
    input      [7:0] a,
    input      [7:0] b,
    input      [3:0] op,
    output reg [7:0] result,
    output reg       c,
    output           z,
    output           n,
    output reg       v
);
    // one separate arithmetic block per op
    wire [8:0] add9 = {1'b0, a} + {1'b0, b};                  // ADD
    wire [7:0] sub8 = a - b;                                  // SUB
    wire [7:0] inc8 = a + 8'd1;                               // INC
    wire [7:0] dec8 = a - 8'd1;                               // DEC
    wire [7:0] neg8 = 8'd0 - a;                               // NEG
    wire       lt_u = (a < b);                                // unsigned compare
    wire       lt_s = ($signed(a) < $signed(b));              // signed compare

    // shifts and rotates: identical to alu.v
    wire        [8:0] sll_t = {1'b0, a} << b;
    wire        [8:0] srl_t = {a, 1'b0} >> b;
    wire signed [8:0] sra_t = $signed({a, 1'b0}) >>> b;
    wire [2:0] k = b[2:0];
    wire [7:0] rol_r = (a << k) | (a >> (4'd8 - k));
    wire [7:0] ror_r = (a >> k) | (a << (4'd8 - k));

    always @(*) begin
        result = 8'h00;  c = 1'b0;  v = 1'b0;
        case (op)
            4'h0: begin result = add9[7:0]; c = add9[8];
                        v = (a[7] == b[7]) && (add9[7] != a[7]); end
            4'h1: begin result = sub8;      c = lt_u;
                        v = (a[7] != b[7]) && (sub8[7] != a[7]); end
            4'h2: begin result = inc8;      c = (a == 8'hFF); v = (a == 8'h7F); end
            4'h3: begin result = dec8;      c = (a == 8'h00); v = (a == 8'h80); end
            4'h4: result = a & b;
            4'h5: result = a | b;
            4'h6: result = a ^ b;
            4'h7: result = ~a;
            4'h8: begin result = sll_t[7:0]; c = sll_t[8]; end
            4'h9: begin result = srl_t[8:1]; c = srl_t[0]; end
            4'hA: begin result = sra_t[8:1]; c = sra_t[0]; end
            4'hB: begin result = rol_r; c = (b != 0) ? rol_r[0] : 1'b0; end
            4'hC: begin result = neg8;      c = (a != 8'h00); v = (a == 8'h80); end
            4'hD: begin result = {7'b0, lt_s}; c = lt_u; end
            4'hE: begin result = {7'b0, lt_u}; c = lt_u; end
            4'hF: begin result = ror_r; c = (b != 0) ? ror_r[7] : 1'b0; end
        endcase
    end

    assign z = (result == 8'h00);
    assign n = result[7];
endmodule
