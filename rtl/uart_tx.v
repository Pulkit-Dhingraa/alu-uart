// uart_tx.v — 8N1 transmitter, LSB first, paced by tick16 (16 ticks = 1 bit).
//
// Frame for tx_data = 0xA5 (1010_0101), sent right-to-left out of the shift register:
//   shreg = {stop=1, 1,0,1,0,0,1,0,1, start=0}
//   wire  :  0 | 1 0 1 0 0 1 0 1 | 1      (start | d0..d7 | stop)
//
// Every bit, including the start bit, lasts exactly 16 ticks = 864 clocks = 8.64 us.
// The start bit is only driven on the first tick AFTER tx_start, so it is never short.
module uart_tx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick16,
    input  wire       tx_start,     // 1-clock pulse; ignored while busy
    input  wire [7:0] tx_data,
    output reg        txd,          // idles high
    output wire       tx_busy
);
    localparam IDLE = 1'b0, SEND = 1'b1;

    reg       state;
    reg [9:0] shreg;      // {stop, d7..d0, start}
    reg [3:0] tick_cnt;   // 0..15 inside one bit
    reg [3:0] bit_cnt;    // 0..9  (start, 8 data, stop)

    assign tx_busy = (state == SEND);

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= IDLE;
            txd      <= 1'b1;
            shreg    <= 10'h3FF;
            tick_cnt <= 0;
            bit_cnt  <= 0;
        end else begin
            case (state)
            IDLE: begin
                txd <= 1'b1;
                if (tx_start) begin
                    shreg    <= {1'b1, tx_data, 1'b0};
                    tick_cnt <= 0;
                    bit_cnt  <= 0;
                    state    <= SEND;
                end
            end
            SEND: if (tick16) begin
                if (tick_cnt == 0)
                    txd <= shreg[0];              // put the next bit on the wire
                if (tick_cnt == 15) begin         // 16 ticks done -> next bit
                    tick_cnt <= 0;
                    shreg    <= {1'b1, shreg[9:1]};
                    if (bit_cnt == 9) state <= IDLE;   // stop bit finished
                    else              bit_cnt <= bit_cnt + 1'b1;
                end else
                    tick_cnt <= tick_cnt + 1'b1;
            end
            endcase
        end
    end
endmodule
