// baud_gen.v — produces a 1-clock pulse "tick16" 16 times per bit.
//
//   DIVISOR = round(CLK_HZ / (BAUD * 16))
//   100 MHz, 115200 baud -> 100e6 / 1,843,200 = 54.25 -> 54
//   Actual tick16 rate = 100e6 / 54      = 1,851,851.9 Hz
//   Actual baud        = 1,851,851.9 / 16 = 115,740.7  (+0.47 % vs 115200)
//
// Integer rounding trick: (a + b/2) / b == round(a / b) for positive integers.
module baud_gen #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115_200
)(
    input  wire clk,
    input  wire rst_n,      // active-low, synchronous (spec v1)
    output reg  tick16
);
    localparam integer DIVISOR = (CLK_HZ + BAUD * 8) / (BAUD * 16);   // = 54
    localparam integer W       = $clog2(DIVISOR);                     // = 6 bits (0..63)

    reg [W-1:0] cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt    <= 0;
            tick16 <= 1'b0;
        end else if (cnt == DIVISOR - 1) begin    // counted 0..53 = 54 clocks
            cnt    <= 0;
            tick16 <= 1'b1;                       // pulse for exactly one clock
        end else begin
            cnt    <= cnt + 1'b1;
            tick16 <= 1'b0;
        end
    end
endmodule
