// ============================================================
// alu.v  -  8-bit ALU, 16 operations (spec v1)
// Purely combinational: no clock, no memory.
// Change a, b or op  ->  result and flags change right away.
// ============================================================
module alu (
    input      [7:0] a,
    input      [7:0] b,
    input      [3:0] op,
    output reg [7:0] result,
    output reg       c,      // carry / borrow / last bit shifted out
    output           z,      // result == 0
    output           n,      // result is negative (bit 7)
    output reg       v       // signed overflow
);

    // --------------------------------------------------------
    // STEP 1: choose what goes into the ONE shared adder
    //         sum = x + y + cin
    // --------------------------------------------------------
    reg [7:0] x, y;
    reg       cin;
    reg       is_sub;        // 1 = this op is a subtraction, C means "borrow"

    always @(*) begin
        // defaults: ADD
        x = a;  y = b;  cin = 1'b0;  is_sub = 1'b0;
        case (op)
            4'h1, 4'hD, 4'hE: begin x = a;     y = ~b;    cin = 1'b1; is_sub = 1'b1; end // SUB, SLT, SLTU : A + ~B + 1
            4'h2:             begin x = a;     y = 8'h00; cin = 1'b1; is_sub = 1'b0; end // INC : A + 0 + 1
            4'h3:             begin x = a;     y = 8'hFF; cin = 1'b0; is_sub = 1'b1; end // DEC : A + FF   (FF = -1)
            4'hC:             begin x = 8'h00; y = ~a;    cin = 1'b1; is_sub = 1'b1; end // NEG : 0 + ~A + 1
            default:          begin end                                                   // ADD and non-adder ops
        endcase
    end

    // --------------------------------------------------------
    // STEP 2: the adder itself (9 bits wide so we keep the carry-out)
    // --------------------------------------------------------
    wire [8:0] sum_full = x + y + cin;
    wire [7:0] sum      = sum_full[7:0];
    wire       cout     = sum_full[8];

    wire add_c = is_sub ? ~cout : cout;                       // subtract: no carry-out = borrow
    wire add_v = (x[7] == y[7]) && (sum[7] != x[7]);          // same-sign inputs, different-sign answer
    wire add_n = sum[7];

    // --------------------------------------------------------
    // STEP 3: shifter helpers (one extra bit catches the bit that falls out)
    // --------------------------------------------------------
    wire        [8:0] sll_t = {1'b0, a} << b;                 // bit 8 = last bit pushed out on the left
    wire        [8:0] srl_t = {a, 1'b0} >> b;                 // bit 0 = last bit pushed out on the right
    wire signed [8:0] sra_t = $signed({a, 1'b0}) >>> b;       // same, but fills with the sign bit

    wire [2:0] k = b[2:0];                                    // rotate amount = B mod 8
    wire [7:0] rol_r = (a << k) | (a >> (4'd8 - k));
    wire [7:0] ror_r = (a >> k) | (a << (4'd8 - k));

    // --------------------------------------------------------
    // STEP 4: pick the result and C, V for this op
    // --------------------------------------------------------
    always @(*) begin
        result = 8'h00;  c = 1'b0;  v = 1'b0;                 // logic and shift ops keep V = 0
        case (op)
            4'h0, 4'h1, 4'h2, 4'h3, 4'hC: begin               // ADD SUB INC DEC NEG
                result = sum;  c = add_c;  v = add_v;
            end
            4'h4: result = a & b;                             // AND
            4'h5: result = a | b;                             // OR
            4'h6: result = a ^ b;                             // XOR
            4'h7: result = ~a;                                // NOT
            4'h8: begin result = sll_t[7:0];  c = sll_t[8]; end   // SLL
            4'h9: begin result = srl_t[8:1];  c = srl_t[0]; end   // SRL
            4'hA: begin result = sra_t[8:1];  c = sra_t[0]; end   // SRA
            4'hB: begin result = rol_r;  c = (b != 0) ? rol_r[0] : 1'b0; end  // ROL
            4'hD: begin result = {7'b0, add_n ^ add_v};  c = add_c; end      // SLT  (signed A<B)
            4'hE: begin result = {7'b0, add_c};          c = add_c; end      // SLTU (unsigned A<B = borrow)
            4'hF: begin result = ror_r;  c = (b != 0) ? ror_r[7] : 1'b0; end  // ROR
        endcase
    end

    // Z and N are the same rule for every op
    assign z = (result == 8'h00);
    assign n = result[7];

endmodule