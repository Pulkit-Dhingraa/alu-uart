# 7. Design Trade-offs

Almost every decision in this project gave me something and cost me something.
This page lists each one: what I chose, what I gained, what I paid, and whether I measured it.

## 7.1 Summary

| # | Decision | I gained | I paid | Evidence |
|---|---|---|---|---|
| 1 | One shared adder | Less area | Lower Fmax | Measured in Vivado |
| 2 | No FIFO | Less area, simpler design | Depends on a timing argument | Calculated and simulated |
| 3 | 16x oversampling | Accurate mid-bit sampling | Coarser divisor, more baud error at high rates | Calculated |
| 4 | Integer baud divisor | A simple 6-bit counter | +0.47% baud error | Calculated and simulated |
| 5 | One sample per bit | Smallest receiver | No noise rejection | Reasoning only |
| 6 | Combinational ALU | No latency, simple | Whole ALU must fit in one clock | Measured in Vivado |
| 7 | `tick16` enable, single clock | One clock domain | Reply waits up to one tick | Simulated |
| 8 | 2-flop synchronisers | Safe against metastability | 2 clocks of delay, 2 flip-flops each | Calculated |
| 9 | Fixed 4-byte request | Simple parser | Wasted byte on one-input operations | Calculated |
| 10 | Header only, no checksum | Shorter packet, higher throughput | Corrupted data is not detected | Reasoning only |
| 11 | Timeout of 480 ticks | Forgives short pauses | Slower recovery from a broken packet | Simulated |
| 12 | Borrow-style C flag | Easy to read: C = 1 means A < B | Differs from some processors | Design choice |
| 13 | Exhaustive ALU test | Complete proof for the ALU | Does not scale to wider designs | Calculated |
| 14 | Synchronous reset | Everything in one clock domain | Reset needs a running clock | Design choice |
| 15 | Behavioural shift operators | Short, readable RTL | I do not control the shifter structure | Design choice |

## 7.2 The trade-offs in detail

### 1. Shared adder: area versus speed

This is the one trade-off I measured directly.

| | Shared adder | Flat (one adder per operation) |
|---|---|---|
| LUTs | 150 | 171 |
| Carry chains (CARRY4) | 3 | 7 |
| Fmax (ALU alone) | 154.4 MHz | 160.6 MHz |

- **Gain:** 21 fewer LUTs (12.3%).
- **Cost:** about 4% lower Fmax. The multiplexer that chooses the adder inputs sits in front of the adder and makes the path longer.
- **Why I accepted it:** my clock is 100 MHz and both versions pass easily. Speed I cannot use is worth less than area I save.
- **When I would choose the other way:** if the ALU were on the critical path of a design that struggled to meet timing.

### 2. No FIFO: area versus safety margin

- **Gain:** no memory, no read and write pointers, no overflow flag, and one less block to verify.
- **Cost:** correctness now depends on an argument about timing (4 frames in, 2 frames out) instead of a buffer that simply absorbs bursts.
- **Why I accepted it:** the spare time is about 174 µs, which is two whole frames. It is not a close call.
- **When I would choose the other way:** if replies were as long as requests, or if the ALU took many clocks.

### 3. Oversampling ratio: sampling accuracy versus divisor resolution

With 16 ticks per bit, I find the middle of a bit to within 1/16 of a bit. But the divisor is f_clk / (BAUD × 16), so a higher oversampling ratio makes the divisor smaller and its rounding error larger.

| Baud | Divisor at 16x | Error |
|---|---|---|
| 9,600 | 651 | +0.006% |
| 115,200 | 54 | +0.47% |
| 921,600 | 7 | −3.12% |

- **Gain:** a small detection error (at most 6.25% of a bit).
- **Cost:** at high baud rates the divisor is too coarse.
- **Alternative:** 8x oversampling would double the divisor and halve the rounding problem, but double the detection error.

### 4. Integer divisor: simplicity versus accuracy

- **Gain:** the baud generator is a 6-bit counter and a comparison.
- **Cost:** +0.47% error at 115,200.
- **Alternative:** a fractional generator adds a fixed step to an accumulator every clock and ticks on overflow. The average rate can be almost exact, but individual ticks jitter by one clock.
- **Why I accepted it:** 0.47% uses about 4.4% of a bit over one frame, out of roughly 50% available.

### 5. One sample per bit: area versus noise immunity

- **Gain:** the receiver needs no extra storage or voting logic.
- **Cost:** one noise spike at the wrong moment gives a wrong bit.
- **Alternative:** sample three times near the middle and take the majority.
- I have no measurement for this one. It is a known weakness.

### 6. Combinational ALU: latency versus clock speed

- **Gain:** the answer is ready one clock after the inputs are stored. No pipeline to control.
- **Cost:** the whole operation must settle within one clock period. The worst ALU path is 6.42 ns of my 10 ns.
- **Why I accepted it:** the serial link is about 54,000 times slower than the ALU. Pipelining the ALU would add flip-flops and gain nothing.

### 7. Tick enable instead of a divided clock

- **Gain:** one clock domain. Vivado can time every path, and I need no extra synchronisers inside the design.
- **Cost:** the transmitter can only start a bit on a tick, so a reply waits up to 54 clocks (540 ns). That is where my reply latency comes from.

### 8. Two-flop synchroniser: reliability versus delay

- **Gain:** a metastable first flip-flop gets a full clock period to settle.
- **Cost:** 2 flip-flops and 2 clocks (20 ns) of delay, which is 0.23% of one bit.
- **Alternative:** 3 flip-flops would be even safer and cost one more clock. At 100 MHz with a slow UART input, 2 is the usual choice.

### 9. Fixed-length request: simplicity versus efficiency

- **Gain:** the parser always collects exactly 3 bytes after the header. Four states, no decoding of the op before reading B.
- **Cost:** INC, DEC, NOT and NEG send a B byte that is ignored. That is 1 byte in 4, or 25% of the request, wasted for those operations.
- **Alternative:** send op first and let it decide the length. This needs a more complex parser.

### 10. No checksum: throughput versus error detection

- **Gain:** 4 bytes per request instead of 5. With 5 bytes, throughput would fall from 2,880 to 115,200 / 50 = 2,304 per second.
- **Cost:** a flipped data bit is not noticed. Only framing problems and illegal ops are caught.

### 11. Timeout length: tolerance versus recovery time

- **Gain:** a pause of up to 2 frames in the middle of a packet is forgiven (test T5a).
- **Cost:** after a truly broken packet, I wait 259 µs before hunting again.
- A shorter timeout recovers faster but may kill packets from a PC that hesitates.

### 12. Borrow-style carry flag

- **Gain:** for SUB, C = 1 means A < B (unsigned), which reads naturally, and SLTU is simply the C flag.
- **Cost:** it is the opposite of processors that keep the raw carry-out on subtraction, so I must state my convention clearly.

### 13. Exhaustive versus random verification

- **Gain:** all 1,048,576 ALU inputs are checked. There are no untested cases.
- **Cost:** this only works because the ALU is small and has no memory. The run takes about a minute.
- For the controller, which has memory, exhaustive testing is impossible. There I used directed tests for each fault plus 1,000 random packets.

### 14. Synchronous versus asynchronous reset

- **Gain:** reset behaves like any other signal: one clock domain, simple timing.
- **Cost:** the design only resets while the clock is running, and the reset must be held for at least a few clocks.

### 15. Shift operators versus a hand-built barrel shifter

- **Gain:** one line of RTL per shift, easy to read and easy to check.
- **Cost:** the synthesis tool decides the structure. I cannot say exactly how many multiplexer stages it built without reading the schematic.
