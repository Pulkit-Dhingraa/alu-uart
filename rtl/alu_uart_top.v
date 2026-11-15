// alu_uart_top.v — everything wired together (spec v2: no FIFO).
//
//  uart_rxd ─► sync2 ─► uart_rx ─► fsm ─► uart_tx ─► uart_txd
//                         ▲         │▲
//                      baud_gen  A,B,op │ result, flags
//                     (tick16 to all)  ▼│
//                                      alu
//
// Pin names follow the Nexys 4 board: uart_rxd is the FPGA's INPUT from the PC.
module alu_uart_top #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115_200
)(
    input  wire clk,          // 100 MHz
    input  wire cpu_resetn,   // CPU_RESET button, active-low
    input  wire uart_rxd,     // PC -> FPGA
    output wire uart_txd      // FPGA -> PC
);
    // ---- reset: the button is asynchronous, so pass it through 2 flops too ----
    reg rst_s1 = 1'b0, rst_s2 = 1'b0;
    always @(posedge clk) begin
        rst_s1 <= cpu_resetn;
        rst_s2 <= rst_s1;
    end
    wire rst_n = rst_s2;

    // ---- wires between blocks ----
    wire       tick16;
    wire       rxd_s;
    wire [7:0] rx_data;
    wire       rx_valid, frame_err;
    wire [7:0] a, b, alu_result;
    wire [3:0] op;
    wire       alu_c, alu_z, alu_n, alu_v;
    wire       tx_start, tx_busy;
    wire [7:0] tx_data;

    baud_gen #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_baud (
        .clk(clk), .rst_n(rst_n), .tick16(tick16));

    sync2 u_sync (
        .clk(clk), .rst_n(rst_n), .d_async(uart_rxd), .q_sync(rxd_s));

    uart_rx u_rx (
        .clk(clk), .rst_n(rst_n), .tick16(tick16), .rxd(rxd_s),
        .rx_data(rx_data), .rx_valid(rx_valid), .frame_err(frame_err));

    fsm u_fsm (
        .clk(clk), .rst_n(rst_n), .tick16(tick16),
        .rx_data(rx_data), .rx_valid(rx_valid), .frame_err(frame_err),
        .a(a), .b(b), .op(op),
        .alu_result(alu_result), .alu_c(alu_c), .alu_z(alu_z), .alu_n(alu_n), .alu_v(alu_v),
        .tx_busy(tx_busy), .tx_start(tx_start), .tx_data(tx_data));

    alu u_alu (
        .a(a), .b(b), .op(op),
        .result(alu_result), .c(alu_c), .z(alu_z), .n(alu_n), .v(alu_v));

    uart_tx u_tx (
        .clk(clk), .rst_n(rst_n), .tick16(tick16),
        .tx_start(tx_start), .tx_data(tx_data),
        .txd(uart_txd), .tx_busy(tx_busy));
endmodule
