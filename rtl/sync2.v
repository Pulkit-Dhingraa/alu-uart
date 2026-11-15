// sync2.v — 2-flop synchroniser for the asynchronous uart_rxd pin.
// The PC's edges arrive at any moment relative to our 100 MHz clock. If an edge lands
// inside a flop's setup/hold window, that flop can go metastable. The second flop gives
// it a full 10 ns clock period to settle before anything else looks at it.
// Cost: 2 clocks of delay = 20 ns, which is 0.2 % of one 8.64 us bit. Negligible.
module sync2 (
    input  wire clk,
    input  wire rst_n,
    input  wire d_async,
    output wire q_sync
);
    reg s1, s2;
    always @(posedge clk) begin
        if (!rst_n) begin s1 <= 1'b1; s2 <= 1'b1; end   // reset to idle-high
        else        begin s1 <= d_async; s2 <= s1; end
    end
    assign q_sync = s2;
endmodule
