# 6. Results and Limitations

## 6.1 What stage each result comes from

| Stage | Done? | Tool | Evidence in this repository |
|---|---|---|---|
| Designed | Yes | Verilog | `rtl/` |
| Simulated | Yes | Icarus Verilog 12 | `sim_logs/`, reproducible with `scripts/run_all_sims.sh` |
| Synthesised, placed and routed | Yes | Vivado 2024.1, part xc7a100tcsg324-1 | Numbers below are copied from my run of 14 Nov 2026. The raw report files are not in the repository yet (see [Things I Need to Confirm](08_things_to_confirm.md)). |
| Run on a board | **No** | | Nothing. I stopped at Vivado. |

## 6.2 Does it work? (simulation)

| Testbench | What it proves | Result | Log |
|---|---|---|---|
| `alu_tb.v` | Every A × B × op against a reference model | 1,048,576 vectors, 0 mismatches | `1_alu_exhaustive.log` |
| `tb_alu_flat_equiv.v` | Flat ALU equals shared-adder ALU | 1,048,576 inputs, 0 differences | `2_alu_flat_equiv.log` |
| `tb_uart_loopback.v` | My TX to my RX, all 256 byte values | 256 / 256, 0 errors | `3_uart_loopback.log` |
| `tb_baud_sweep.v` | Baud mismatch tolerance | Pass −5.25% to +4.55%, fail at −5.30% and +4.60% | `4_baud_sweep.log` |
| `tb_top.v` | Whole design through the pins | 2,024 / 2,024 reply bytes, 0 mismatches | `5_top_end_to_end.log` |

## 6.3 How fast is it?

| Quantity | Value | Source |
|---|---|---|
| Throughput | 2,880 operations per second | Simulation, and [Calculations 5.8](05_calculations.md) |
| What limits it | The serial link: one request is 347.2 µs | Derived |
| Reply latency | 530 ns (53 clocks) as the testbench measures it | Simulation, explained in [Calculations 5.10](05_calculations.md) |
| Worst ALU path, register to register | 6.42 ns | Vivado (ALU alone) |
| Link compared with ALU | about 54,000 times slower | Derived |

## 6.4 Baud and timing error

| Quantity | Value | Source |
|---|---|---|
| Divisor | 54 (exact value 54.25) | Derived, confirmed by the loopback measurement |
| Actual baud | 115,740.7 | Derived |
| Baud error | +0.47% | Derived |
| Tolerance, theory | −5.26% to +4.58% | Derived |
| Tolerance, measured | −5.25% to +4.55% | Simulation |

## 6.5 How much hardware? (Vivado, after place and route)

| Run | LUTs | Flip-flops | CARRY4 | WNS at 10 ns | Worst path delay | Fmax |
|---|---|---|---|---|---|---|
| ALU alone, shared adder | 150 | 31 (in the wrapper, the ALU has none) | 3 | 3.525 ns | 6.420 ns | 154.4 MHz |
| ALU alone, flat | 171 | 31 | 7 | 3.772 ns | 6.221 ns | 160.6 MHz |
| **Full design** | **235** | **119** | 3 | **3.394 ns** | 6.276 ns | **151.4 MHz** |

Notes on reading this table:

- **"ALU alone"** means the ALU with flip-flops on its inputs and outputs (`syn/alu_wrap.v`), so Vivado has a register-to-register path to time. It was built "out of context", meaning without I/O pins.
- **Fmax** is 1 / (10 ns − WNS). The working is in [Calculations 5.13](05_calculations.md).
- **Worst path delay** is the delay of the logic and wires on the slowest path. It is a little smaller than 10 ns − WNS because the slack also accounts for the flip-flop's setup time and clock effects.
- **The full-design number (151.4 MHz) is the one I quote.** The ALU-alone runs do not model clock skew.
- Timing is met at 100 MHz with 3.394 ns to spare. Hold slack after routing was +0.166 ns.
- The full design uses 0.37% of the LUTs and 0.09% of the flip-flops of the XC7A100T.

**Shared adder versus flat:** 21 fewer LUTs (12.3%), 3 carry chains instead of 7, and about 4% lower Fmax.

## 6.6 Limitations

| # | Limitation | Why it matters |
|---|---|---|
| 1 | **Never run on hardware.** | Simulation and Vivado say it should work. I have not seen it work on a board. |
| 2 | **No checksum.** | A corrupted data byte with a good stop bit gives a wrong answer with no warning. |
| 3 | **One sample per bit.** | No majority voting, so a noise spike at the sampling moment flips a bit. |
| 4 | **Header can appear in data.** | After losing sync, the parser might lock onto an `A5` that was really A or B. |
| 5 | **Fmax is an estimate.** | It comes from one run at 10 ns. I did not push the constraint to find the true limit. |
| 6 | **Baud tested at one rate.** | Only 115,200 was simulated. The other rows in my baud table are paper calculations. |
| 7 | **Only the PC-to-FPGA tolerance was measured.** | The PC must also accept my +0.47%. I assumed it can. |
| 8 | **The link wastes the ALU.** | The ALU could run about 54,000 times faster than the link feeds it. |
| 9 | **B is always sent.** | One-input operations (INC, DEC, NOT, NEG) still send a B byte that is ignored. |
| 10 | **No power numbers.** | I did not run a power report, so I make no power claims. |

## 6.7 Possible improvements

| Improvement | What it fixes | Cost |
|---|---|---|
| Checksum byte in the request | Limitation 2 and 4 | One more byte per request, slower throughput |
| 3-sample majority vote in the receiver | Limitation 3 | A few flip-flops and LUTs |
| Fractional baud generator | Larger baud error at high baud rates | A wider accumulator instead of a simple counter |
| Run on the Nexys 4 with a PC script | Limitation 1 | Time and a board |
| Re-run Vivado with tighter clocks | Limitation 5 | A few more runs |
