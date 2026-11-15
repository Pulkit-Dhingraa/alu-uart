# 5. Calculations and Mathematical Reasoning

Every number that appears anywhere in this repository is worked out here.

Each calculation is labelled with where its inputs come from:

- **Design choice**: a value I picked.
- **Derived**: calculated from other values.
- **Simulation**: measured in Icarus Verilog (logs in `sim_logs/`).
- **Vivado**: read from my Vivado 2024.1 run after place and route.

## 5.1 The starting values

| Symbol | Meaning | Value | Source |
|---|---|---|---|
| f_clk | Clock frequency | 100,000,000 Hz | Fixed by the Nexys 4 board |
| T_clk | Clock period = 1 / f_clk | 10 ns | Derived |
| BAUD | Wanted baud rate | 115,200 bits/s | Design choice |
| OS | Oversampling: ticks per bit | 16 | Design choice |
| N_frame | Bits in one frame (1 start + 8 data + 1 stop) | 10 | Design choice (8N1) |
| N_req | Bytes in a request | 4 | Design choice |
| N_rep | Bytes in a reply | 2 | Design choice |

## 5.2 The baud divisor

**What I need:** how many clocks to count between two ticks.

```math
\boxed{\;\text{DIVISOR} = \text{round}\!\left(\frac{f_{clk}}{\text{BAUD} \times \text{OS}}\right)\;}
```

**Substitute:**

```math
\frac{100{,}000{,}000}{115{,}200 \times 16} = \frac{100{,}000{,}000}{1{,}843{,}200} = 54.25
```

I cannot count a quarter of a clock, so I round to the nearest whole number: **DIVISOR = 54**.

**How the RTL rounds.** Verilog integer division drops the fraction. Adding half of the divider first turns that into rounding:

```math
\boxed{\;\text{round}\!\left(\frac{a}{b}\right) = \left\lfloor \frac{a + b/2}{b} \right\rfloor\;}
```

With a = 100,000,000 and b = 1,843,200, half of b is 921,600, which is BAUD × 8:

```math
\left\lfloor \frac{100{,}000{,}000 + 921{,}600}{1{,}843{,}200} \right\rfloor = \lfloor 54.75 \rfloor = 54
```

This is exactly the line in `baud_gen.v`: `(CLK_HZ + BAUD * 8) / (BAUD * 16)`.

**Counter width:** to count from 0 to 53 I need ceil(log2(54)) = 6 bits, because 2^6 = 64 is the first power of two that is at least 54.

## 5.3 The baud rate I actually get

```math
\boxed{\;\text{BAUD}_{actual} = \frac{f_{clk}}{\text{DIVISOR} \times \text{OS}}\;}
```

```math
\frac{100{,}000{,}000}{54 \times 16} = \frac{100{,}000{,}000}{864} = 115{,}740.7 \text{ bits/s}
```

**What it means:** one of my bits is 864 clocks long. I am slightly faster than the PC.

## 5.4 Baud error

```math
\boxed{\;\text{error} = \frac{\text{BAUD}_{actual} - \text{BAUD}}{\text{BAUD}} \times 100\%\;}
```

```math
\frac{115{,}740.7 - 115{,}200}{115{,}200} \times 100\% = \frac{540.7}{115{,}200} \times 100\% = +0.47\%
```

The same calculation for other baud rates (derived on paper only; I simulated 115,200 only):

| Baud | Exact divisor | Used | Actual baud | Error |
|---|---|---|---|---|
| 9,600 | 651.04 | 651 | 9,600.6 | +0.006% |
| 115,200 | 54.25 | 54 | 115,740.7 | +0.47% |
| 921,600 | 6.78 | 7 | 892,857.1 | −3.12% |

**What it means:** the error comes from rounding. A big divisor rounds almost perfectly. A small divisor cannot, because a step of 1 is a large fraction of 7.

## 5.5 Bit time and frame time

```math
\boxed{\;T_{bit} = \frac{1}{\text{BAUD}} \qquad T_{frame} = N_{frame} \times T_{bit}\;}
```

| | One bit | One frame (10 bits) |
|---|---|---|
| PC, at 115,200 | 1 / 115,200 = 8.681 µs | 86.81 µs |
| My design, at 115,740.7 | 864 × 10 ns = 8.640 µs | 86.40 µs |
| One tick (1/16 of my bit) | 54 × 10 ns = 540 ns | |

Simulation agrees: the loopback log reports 864 clocks per bit and 86.40 µs per frame.

## 5.6 How much baud mismatch my receiver survives

**The setup.** My receiver only looks at the line once per tick.

1. It notices the start edge between 0 and 1 tick late. Call this delay d, from 0 to 1/16 of a bit.
2. From that moment it counts 152 ticks = 9.5 of my bit times, and samples the stop bit.

The stop bit on the wire lasts from 9 to 10 PC bit times after the real start edge. My sample must land inside it.

```math
\boxed{\;9\,T_{PC} \;<\; d + 9.5\,T_{mine} \;<\; 10\,T_{PC}\;}
```

**Case 1: the PC is faster than me** (its bits are shorter). My sample arrives late, and the worst case is the latest detection, d = T_mine / 16.

```math
\frac{T_{mine}}{16} + 9.5\,T_{mine} < 10\,T_{PC} \quad\Rightarrow\quad \frac{T_{PC}}{T_{mine}} > \frac{9.5625}{10}
```

Baud is 1 / T, so the PC's baud can be at most 10 / 9.5625 times mine:

```math
\boxed{\;\text{PC faster limit} = \frac{10}{9.5625} - 1 = +4.58\%\;}
```

**Case 2: the PC is slower than me** (its bits are longer). My sample arrives early, and the worst case is instant detection, d = 0.

```math
9.5\,T_{mine} > 9\,T_{PC} \quad\Rightarrow\quad \frac{T_{PC}}{T_{mine}} < \frac{9.5}{9}
```

```math
\boxed{\;\text{PC slower limit} = \frac{9}{9.5} - 1 = -5.26\%\;}
```

**Compare with simulation:**

| | Theory | Simulation: last pass | Simulation: first fail |
|---|---|---|---|
| PC faster | +4.58% | +4.55% | +4.60% |
| PC slower | −5.26% | −5.25% | −5.30% |

Theory falls between the last pass and the first fail on both sides.

**Why it is lopsided:** the detection delay d is always "late", never "early". It eats into the margin on one side only.

**A concrete example at my real rates.** PC at 115,200, me at 115,740.7. Times are measured from the real start edge.

| Event | Time |
|---|---|
| PC's stop bit begins (9 PC bits) | 78.13 µs |
| Middle of the PC's stop bit (9.5 PC bits) | 82.47 µs |
| My stop sample, if I saw the edge instantly (9.5 of my bits) | 82.08 µs |
| My stop sample, if I saw the edge a full tick late (+0.54 µs) | 82.62 µs |
| PC's stop bit ends (10 PC bits) | 86.81 µs |

My sample lands between 0.39 µs early and 0.15 µs late of the centre. The nearest edge of the stop bit is more than 3.9 µs away.

```math
\text{drift at the stop bit} = 9.5 \times 0.47\% \approx 4.4\% \text{ of one bit}
```

**How much error is left for the PC?** The PC at exactly 115,200 is already 0.47% slower than me, so it sits at m = −0.47% inside my −5.25% to +4.55% window. In PC baud that window is:

```math
115{,}740.7 \times 0.9475 = 109{,}664 \qquad 115{,}740.7 \times 1.0455 = 121{,}007
```

Compared with 115,200, that is −4.8% to +5.0%. So the PC's own clock can be about 4.8% slow or 5.0% fast before my receiver fails. I describe this as "about ±4.5%" to stay on the safe side.

This covers the PC-to-FPGA direction only. For the other direction, the PC's receiver must tolerate my +0.47%. I have not measured that.

## 5.7 Number of ALU test vectors

```math
\boxed{\;N_{vectors} = 2^{\,\text{input bits}}\;}
```

The ALU inputs are A (8 bits), B (8 bits) and op (4 bits): 20 bits in total.

```math
2^{8+8+4} = 2^{20} = 256 \times 256 \times 16 = 1{,}048{,}576
```

**What it means:** small enough to test every case. For comparison, a 32-bit ALU with the same op width has 2^68 inputs, about 3 × 10^20, which can never be tested exhaustively.

## 5.8 Throughput

A request is 4 frames. The PC sends them back-to-back, and I can only reply once a request is complete. So the PC's sending rate is the limit.

```math
\boxed{\;T_{request} = N_{req} \times N_{frame} \times T_{bit,PC} \qquad \text{throughput} = \frac{1}{T_{request}}\;}
```

```math
T_{request} = 4 \times 10 \times 8.681\ \mu s = 347.2\ \mu s
```

```math
\text{throughput} = \frac{115{,}200}{40} = 2{,}880 \text{ operations per second}
```

Simulation agrees: `reply rate measured = 2880.0 ops/s`.

Note: the rate depends on the **PC's** bit time, because the PC is the one sending the requests. With my own bit time the same calculation would give 345.6 µs and 2,894 per second, but the PC does not send that fast.

**How much slower is the link than the ALU?**

```math
\frac{T_{request}}{T_{ALU\ path}} = \frac{347.2\ \mu s}{6.42\ ns} \approx 54{,}000
```

The 6.42 ns is the worst ALU path from Vivado (section 5.13). The link is about 54,000 times slower than the ALU. Making the ALU faster would change nothing.

## 5.9 Why I do not need a FIFO

```math
\boxed{\;\text{spare time} = T_{request} - T_{reply} - T_{latency}\;}
```

| Quantity | Calculation | Value |
|---|---|---|
| Time for the next request to arrive | 4 frames × 86.81 µs | 347.2 µs |
| Time to send my reply | 2 frames × 86.40 µs | 172.8 µs |
| Reply latency | section 5.10 | about 0.5 µs |
| **Spare time** | 347.2 − 172.8 − 0.5 | **about 173.9 µs** |

**What it means:** the sender has been idle for about 2 frames by the time the next request is complete. Nothing ever has to wait, so there is nothing to buffer.

The limit: this holds while a reply takes less time than a request. If the PC's baud were more than twice mine it would break, but my receiver stops working long before that (section 5.6).

## 5.10 Reply latency

Counted in clocks from the `tick16` on which the stop bit of the op byte is sampled:

| Clock | Event |
|---|---|
| 0 | `tick16`: stop bit sampled |
| 1 | `rx_valid` is high |
| 2 | `calc` is high (op byte stored) |
| 3 | sender has latched result and status |
| 4 | `tx_start` is high |
| 5 | `tx_busy` is high, transmitter waits for a tick |
| 54 | the next `tick16` |
| 55 | `uart_txd` goes low: start bit |

From `rx_valid` rising (clock 1) to the start bit (clock 55):

```math
\text{latency} = 55 - 1 = 54 \text{ clocks} = 540\ ns
```

The testbench reports **530 ns (53 clocks)** because it notices `rx_valid` one clock edge after it rises. Both describe the same waveform.

**What it means:** the ALU and the controller only use 4 of those clocks. The rest is the transmitter waiting for the next tick. The latency is essentially one tick period.

## 5.11 The timeout

```math
\boxed{\;T_{timeout} = \text{TIMEOUT\_TICKS} \times T_{tick}\;}
```

```math
480 \times 540\ ns = 259.2\ \mu s
```

One frame is 160 ticks (10 bits × 16), so 480 ticks is 3 frames. The counter restarts when a byte **finishes** arriving. The next byte needs 1 frame to arrive, so 3 frames between bytes means:

```math
3 \text{ frames} - 1 \text{ frame for the byte itself} = 2 \text{ frames of real silence}
```

Counter width: counting to 480 needs 9 bits, because 2^9 = 512.

**Check against my tests:**

| Test | Gap after the previous byte ends | Compared with 259.2 µs | Result |
|---|---|---|---|
| T5a | 12 idle bits + 10 bits of the next byte = 22 × 8.681 = 191 µs | shorter | No timeout, reply sent |
| T5b | 40 idle bits = 347 µs with nothing arriving | longer | Timeout, half packet dropped |

480 is a design choice. It is long enough to forgive a short pause and short enough to recover quickly.

## 5.12 Flip-flop count from the RTL

I counted every register in my RTL and compared it with Vivado.

| Module | Registers | Count |
|---|---|---|
| `alu_uart_top` | reset synchroniser (2) | 2 |
| `sync2` | s1, s2 | 2 |
| `baud_gen` | cnt (6), tick16 (1) | 7 |
| `uart_rx` | state (2), tick_cnt (4), bit_cnt (3), shreg (8), rx_data (8), rx_valid (1), frame_err (1) | 27 |
| `uart_tx` | state (1), shreg (10), tick_cnt (4), bit_cnt (4), txd (1) | 20 |
| `fsm` | rx_state (2), tx_state (2), a (8), b (8), op_byte (8), calc (1), res_q (8), stat_q (8), tx_start (1), tx_data (8), frame_sticky (1), to_cnt (9) | 64 |
| `alu` | none, it is combinational | 0 |
| **Total in the RTL** | | **122** |

Vivado reports **119**. The difference is 3.

My explanation, which I still need to confirm in the utilisation report: Vivado removes flip-flops that can never change. Two bits of `stat_q` (bit 7 and bit 5) are always 0, and the top bit of the transmit shift register is always 1. That is exactly 3.

## 5.13 Maximum frequency from the Vivado slack

Vivado checks every path against my 10 ns clock and reports the worst negative slack (WNS). A positive WNS is the time left over on the slowest path.

```math
\boxed{\;F_{max} = \frac{1}{T_{clk} - \text{WNS}}\;}
```

| Run | WNS (Vivado) | T_clk − WNS | Fmax |
|---|---|---|---|
| ALU alone, shared adder | 3.525 ns | 6.475 ns | 1 / 6.475 ns = 154.4 MHz |
| ALU alone, flat | 3.772 ns | 6.228 ns | 1 / 6.228 ns = 160.6 MHz |
| **Full design** | **3.394 ns** | **6.606 ns** | **1 / 6.606 ns = 151.4 MHz** |

**What it means:** the slowest path in my full design needs 6.606 ns, and I gave it 10 ns. It would still work with a clock up to about 151 MHz.

This is an estimate from a single run at 10 ns. To be sure of the real maximum I would have to re-run Vivado with a tighter clock constraint.

## 5.14 Shared adder versus flat: the saving

```math
\boxed{\;\text{saving} = \frac{\text{LUTs}_{flat} - \text{LUTs}_{shared}}{\text{LUTs}_{flat}} \times 100\%\;}
```

```math
\frac{171 - 150}{171} \times 100\% = \frac{21}{171} \times 100\% = 12.3\%
```

Carry chains (CARRY4 blocks): 7 in the flat version, 3 in the shared version.

```math
\frac{7 - 3}{7} \times 100\% = 57\% \text{ fewer}
```

The price in speed:

```math
\frac{160.6}{154.4} = 1.04 \quad\Rightarrow\quad \text{the flat ALU is about } 4\% \text{ faster}
```

## 5.15 How much of the FPGA I use

```math
\boxed{\;\text{utilisation} = \frac{\text{used}}{\text{available}} \times 100\%\;}
```

The XC7A100T has 63,400 LUTs and 126,800 flip-flops.

| Resource | Used | Available | Utilisation |
|---|---|---|---|
| LUTs | 235 | 63,400 | 0.37% |
| Flip-flops | 119 | 126,800 | 0.09% |

## 5.16 Cost of the synchroniser

The 2-flop synchroniser delays the PC's signal by 2 clocks.

```math
\frac{2 \times 10\ ns}{8{,}640\ ns} \times 100\% = 0.23\% \text{ of one bit}
```

It is a fixed delay on every edge, so it does not move my sampling point relative to the data.

---

## Formula Reference

| # | Formula | Variables | When I use it | My value |
|---|---|---|---|---|
| F1 | DIVISOR = round(f_clk / (BAUD × OS)) | f_clk = clock frequency, BAUD = wanted bits per second, OS = ticks per bit | Setting the baud counter in `baud_gen.v` | round(54.25) = 54 |
| F2 | round(a / b) = floor((a + b/2) / b) | a, b = positive integers | Rounding with integer division in Verilog | floor(54.75) = 54 |
| F3 | BAUD_actual = f_clk / (DIVISOR × OS) | as above | Finding the rate I really run at | 115,740.7 |
| F4 | error = (BAUD_actual − BAUD) / BAUD | as above | Baud error | +0.47% |
| F5 | T_bit = 1 / BAUD, T_frame = N_frame × T_bit | N_frame = 10 bits | Bit and frame times | 8.640 µs, 86.40 µs (mine) |
| F6 | 9 T_PC < d + 9.5 T_mine < 10 T_PC | d = start detection delay, 0 to T_mine / 16 | Baud mismatch tolerance of `uart_rx.v` | −5.26% to +4.58% |
| F7 | N_vectors = 2^(input bits) | input bits = 8 + 8 + 4 | Size of the exhaustive ALU test | 1,048,576 |
| F8 | throughput = 1 / (N_req × N_frame × T_bit,PC) | N_req = 4 bytes | Operations per second | 2,880 |
| F9 | spare = T_request − T_reply − T_latency | | Proving no FIFO is needed | about 173.9 µs |
| F10 | T_timeout = TIMEOUT_TICKS × T_tick | T_tick = 540 ns | Timeout in `fsm.v` | 259.2 µs |
| F11 | F_max = 1 / (T_clk − WNS) | WNS = worst slack from Vivado | Maximum clock frequency | 151.4 MHz |
| F12 | saving = (flat − shared) / flat | LUT counts from Vivado | Shared adder benefit | 12.3% |
| F13 | utilisation = used / available | | How full the FPGA is | 0.37% LUTs |
| F14 | −B = ~B + 1 | B = 8-bit value | Negation and subtraction in `alu.v` | 3 becomes FD |
| F15 | A − B = A + ~B + 1 | | SUB, SLT, SLTU on the shared adder | 05 − 03 = 02 |
| F16 | V = (x7 = y7) and (sum7 ≠ x7) | x, y = adder inputs, bit 7 = sign | Signed overflow flag | 7F + 01 gives V = 1 |
| F17 | C = cout for add, ~cout for subtract | cout = bit 8 of the sum | Carry and borrow flag | 03 − 05 gives C = 1 |
| F18 | SLT = N xor V of (A − B) | N = sign of the difference | Signed compare | 80 vs 01 gives 1 |
| F19 | SLTU = borrow of (A − B) | | Unsigned compare | 80 vs 01 gives 0 |
| F20 | k = B mod 8, ROL = (A << k) \| (A >> (8 − k)) | k = rotate amount | Rotates | 81 by 1 gives 03 |
