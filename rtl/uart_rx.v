// uart_rx.v — 8N1 receiver with 16x oversampling. Input must already be synchronised
// (see sync2.v). Outputs are 1-clock pulses.
//
// Timing, counted in ticks after the tick where the line is first seen low (the start edge):
//   tick  8  : middle of start bit -> still 0?  yes = real start, no = glitch, go back to IDLE
//   tick 24  : middle of d0
//   tick 40  : middle of d1      ... every 16 ticks ...
//   tick 136 : middle of d7
//   tick 152 : middle of stop    -> 1 = rx_valid, 0 = frame_err (byte dropped)
// Then straight back to IDLE, half a bit early, so the next start edge is never missed.
//
// 152 ticks = 9.5 bits. That 9.5 is where the mismatch tolerance comes from.
module uart_rx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick16,
    input  wire       rxd,          // synchronised serial input
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        frame_err
);
    localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    reg [1:0] state;
    reg [3:0] tick_cnt;
    reg [2:0] bit_cnt;
    reg [7:0] shreg;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE; tick_cnt <= 0; bit_cnt <= 0; shreg <= 0;
            rx_data <= 0; rx_valid <= 1'b0; frame_err <= 1'b0;
        end else begin
            rx_valid  <= 1'b0;          // default: pulses last one clock
            frame_err <= 1'b0;
            if (tick16) begin
                case (state)
                IDLE:
                    if (!rxd) begin                 // line went low: maybe a start bit
                        tick_cnt <= 0;
                        state    <= START;
                    end
                START:
                    if (tick_cnt == 7) begin        // 8 ticks later = middle of start bit
                        tick_cnt <= 0;
                        bit_cnt  <= 0;
                        state    <= rxd ? IDLE : DATA;   // high again = glitch, ignore
                    end else
                        tick_cnt <= tick_cnt + 1'b1;
                DATA:
                    if (tick_cnt == 15) begin       // 16 ticks later = middle of next bit
                        tick_cnt <= 0;
                        shreg    <= {rxd, shreg[7:1]};   // LSB arrives first
                        if (bit_cnt == 7) state <= STOP;
                        else              bit_cnt <= bit_cnt + 1'b1;
                    end else
                        tick_cnt <= tick_cnt + 1'b1;
                STOP:
                    if (tick_cnt == 15) begin       // middle of stop bit
                        tick_cnt <= 0;
                        if (rxd) begin rx_data <= shreg; rx_valid <= 1'b1; end
                        else           frame_err <= 1'b1;
                        state <= IDLE;
                    end else
                        tick_cnt <= tick_cnt + 1'b1;
                endcase
            end
        end
    end
endmodule
