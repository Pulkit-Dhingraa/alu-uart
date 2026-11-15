// fsm.v — packet controller, NO FIFO (spec v2).
//
// Request : 0xA5, A, B, op      Reply : result, status
// status  : bit7=0 | 6 FRAME_ERR | 5 reserved (0) | 4 BAD_OP | 3 V | 2 N | 1 Z | 0 C
//
// Why no FIFO is needed: the controller is split into TWO small machines that run side by side.
//
//   RX parser  (HUNT -> GET_A -> GET_B -> GET_OP)  takes a byte the SAME clock rx_valid pulses.
//              It never waits for anything, so no byte can ever be missed.
//   TX sender  (TX_IDLE -> SEND_R -> SEND_S)       sends the 2-byte reply in the background.
//
// Example, PC sends two packets back-to-back: [A5 05 03 00][A5 10 20 00]
//   t = 0..4 frames   parser collects A5 05 03 00          -> calc pulse
//   +1 clock          sender latches result 08, status 00  -> starts sending [08]
//   t = 4..5 frames   wire OUT: [08]       wire IN: [A5]    (parser takes A5 while TX is busy)
//   t = 5..6 frames   wire OUT: [00]       wire IN: [10]
//   t = 6 frames      sender is idle again; parser still needs [20] and [00]
//   t = 8 frames      second calc pulse -> sender has been idle for 2 frames already
// A request takes 4 frames to arrive, a reply takes 2 frames to leave, so the sender is
// ALWAYS finished before the next calc pulse. That margin is what the FIFO used to buy.
//
// Abort rules (parser goes back to HUNT, no reply):
//   - frame_err mid-packet, or
//   - no byte for 480 tick16 ticks mid-packet. The counter restarts at every received byte,
//     and the next byte itself takes 160 ticks (1 frame) to arrive, so 480 = 1 frame for the
//     byte + 320 ticks (2 frames) of real silence on the line.
module fsm #(
    parameter integer TIMEOUT_TICKS = 480     // byte-to-byte; = 2 frames of silence
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick16,
    // RX side (straight from uart_rx, 1-clock pulses)
    input  wire [7:0] rx_data,
    input  wire       rx_valid,
    input  wire       frame_err,
    // ALU side
    output reg  [7:0] a,
    output reg  [7:0] b,
    output wire [3:0] op,
    input  wire [7:0] alu_result,
    input  wire       alu_c, alu_z, alu_n, alu_v,
    // TX side
    input  wire       tx_busy,
    output reg        tx_start,
    output reg  [7:0] tx_data
);
    localparam [1:0] HUNT = 2'd0, GET_A = 2'd1, GET_B = 2'd2, GET_OP = 2'd3;      // parser
    localparam [1:0] TX_IDLE = 2'd0, SEND_R = 2'd1, SEND_S = 2'd2;                // sender

    reg [1:0] rx_state, tx_state;
    reg [7:0] op_byte;                // full op byte kept for the BAD_OP check
    reg       calc;                   // 1-clock pulse: A, B, op are complete
    reg [7:0] res_q, stat_q;          // reply, latched when calc arrives
    reg       frame_sticky;
    reg [8:0] to_cnt;                 // timeout counter, in tick16 ticks (0..480)

    assign op = op_byte[3:0];

    wire mid_packet = (rx_state != HUNT);
    wire timeout    = (to_cnt == TIMEOUT_TICKS);
    wire bad_op     = (op_byte[7:4] != 4'h0);

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_state <= HUNT;  tx_state <= TX_IDLE;
            a <= 0;  b <= 0;  op_byte <= 0;  calc <= 1'b0;
            res_q <= 0;  stat_q <= 0;  tx_start <= 1'b0;  tx_data <= 0;
            frame_sticky <= 1'b0;  to_cnt <= 0;
        end else begin
            tx_start <= 1'b0;                          // pulses last one clock
            calc     <= 1'b0;

            // ---- timeout counter: runs only mid-packet while nothing arrives ----
            if (!mid_packet || rx_valid) to_cnt <= 0;
            else if (tick16)             to_cnt <= to_cnt + 1'b1;

            // ================= RX parser =================
            case (rx_state)
            HUNT:
                if (rx_valid && rx_data == 8'hA5) rx_state <= GET_A;   // everything else is discarded

            GET_A:
                if (frame_err)     rx_state <= HUNT;
                else if (rx_valid) begin a <= rx_data; rx_state <= GET_B; end
                else if (timeout)  rx_state <= HUNT;

            GET_B:
                if (frame_err)     rx_state <= HUNT;
                else if (rx_valid) begin b <= rx_data; rx_state <= GET_OP; end
                else if (timeout)  rx_state <= HUNT;

            GET_OP:
                if (frame_err)     rx_state <= HUNT;
                else if (rx_valid) begin op_byte <= rx_data; calc <= 1'b1; rx_state <= HUNT; end
                else if (timeout)  rx_state <= HUNT;
            endcase

            // ================= TX sender =================
            case (tx_state)
            TX_IDLE:
                if (calc) begin                        // A, B, op were registered last clock:
                    if (bad_op) begin                  // the ALU has had a full clock to settle
                        res_q  <= 8'h00;
                        stat_q <= {1'b0, frame_sticky, 1'b0, 1'b1, 4'b0000};
                    end else begin
                        res_q  <= alu_result;
                        stat_q <= {1'b0, frame_sticky, 1'b0, 1'b0, alu_v, alu_n, alu_z, alu_c};
                    end
                    frame_sticky <= 1'b0;              // reported -> clear (a new set below wins)
                    tx_state <= SEND_R;
                end
                // calc can only arrive here: see the 4-frames-in vs 2-frames-out argument above.

            // "!tx_start" covers the 1-clock gap before tx_busy rises after a start pulse
            SEND_R:
                if (!tx_busy && !tx_start) begin
                    tx_data <= res_q;  tx_start <= 1'b1;  tx_state <= SEND_S;
                end

            SEND_S:
                if (!tx_busy && !tx_start) begin
                    tx_data <= stat_q; tx_start <= 1'b1;  tx_state <= TX_IDLE;
                end

            default: tx_state <= TX_IDLE;
            endcase

            // ---- sticky error flag: written last, so "set" beats the sender's "clear" ----
            if (frame_err) frame_sticky <= 1'b1;
        end
    end
endmodule
