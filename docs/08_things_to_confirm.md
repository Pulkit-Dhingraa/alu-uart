# 8. Things I Need to Confirm

Open items. Nothing here is hidden in the other pages: wherever one of these affects a number or a claim, that page says so.

## Evidence I still need to add

| # | Item | Why | What to do |
|---|---|---|---|
| 1 | **Raw Vivado reports are not in the repository.** | The LUT, flip-flop, WNS and Fmax numbers come from my run of 14 Nov 2026 (Vivado 2024.1). Only the summary values are recorded here. | Copy the `reports/` folder from that run into `syn/reports/` and check every number in [Results 6.5](06_results_and_limitations.md) against it. |
| 2 | **`syn/run_vivado.tcl` has new file paths.** | I moved the design files into `rtl/` and edited the paths in the script. The edited script has not been run in Vivado. | Run `source run_vivado.tcl` from `syn/` once and confirm the same numbers come out. |
| 3 | **`scripts/run_all_sims.bat` has new file paths.** | Same reason. The Linux script `run_all_sims.sh` was run and passes. The Windows one was only edited. | Run it once on Windows. |

## Explanations that are educated guesses

| # | Claim | Where | How to confirm |
|---|---|---|---|
| 4 | The 3 flip-flops Vivado removed (122 in RTL, 119 reported) are the two constant bits of `stat_q` and the constant top bit of the transmit shift register. | [Calculations 5.12](05_calculations.md) | Look for "removed" or "constant" messages in the synthesis log, or count registers per module in the hierarchical utilisation report. |
| 5 | The ALU wrapper shows 31 flip-flops, but the RTL of `alu_wrap.v` has 32 (8 + 8 + 4 + 8 + 4). | [Results 6.5](06_results_and_limitations.md) | Find which one was removed or merged in the report. I do not have an explanation yet. |
| 6 | Which path is the worst path in the full design (6.276 ns). I expect it to run from the A, B, op registers through the ALU to the result and status registers. | [Results 6.5](06_results_and_limitations.md) | Read the start and end points in `top_timing_paths.rpt`. |
| 7 | Why the shared ALU has 3 CARRY4 blocks. An 8-bit adder needs 2 (4 bits each). I have not traced the third. | [Results 6.5](06_results_and_limitations.md) | Open the schematic or the utilisation report. |
| 8 | The flat ALU is faster "because there is no multiplexer in front of the adder". This is the expected reason, but I have not compared the two timing paths. | [Trade-offs 7.2](07_tradeoffs.md) | Compare the logic levels in the two timing path reports. |
| 9 | Why I picked `A5` as the header. The reason written in the architecture page (a pattern with many edges, unlike a stuck line) is the usual one. | [Architecture 1.7](01_architecture.md) | Replace it with my own reason if it was different. |
| 10 | The "bugs and surprises" table is rebuilt from code comments and project notes. | [Verification 4.8](04_verification.md) | Add the bugs I actually remember hitting, especially from the first attempt at this project. |

## Things that were never tested

| # | Item | Status |
|---|---|---|
| 11 | Running on the Nexys 4 board | Not done |
| 12 | Baud rates other than 115,200 | Paper calculation only |
| 13 | The real PC's baud accuracy (the USB-UART chip) | Not measured. My tolerance leaves about −4.8% to +5.0% for it. |
| 14 | The FPGA-to-PC direction (the PC accepting my +0.47%) | Assumed |
| 15 | Noise on the serial line | Not modelled |
| 16 | That `calc` can never arrive while the sender is busy | Argued by timing and covered indirectly by T8 and the random test, but there is no direct check in the testbench |
| 17 | Power | No report was run |

## Small clean-ups in my files

These are comment-level only. I have left the RTL exactly as I wrote it.

| # | File | Issue |
|---|---|---|
| 18 | `rtl/alu.v` | The header comment still says "spec v1". |
| 19 | `tb/alu_tb.v` | The header comment calls the file `tb_alu.v`, and the module is named `tb_alu`. |
| 20 | `rtl/fsm.v` | The parameter comment says "= 2 frames of silence". The value 480 is 3 frames byte-to-byte, which is 2 frames of silence plus 1 frame for the byte. The longer comment above it explains this correctly. |
| 21 | `tb/tb_top.v` | My earlier notes said "10 directed tests". The log shows 11 checks covering 12 replies (T1 to T8, with a and b variants). I use the log's numbers. |

## Before publishing

- Add my name and a licence to the README if I want them.
- Decide the repository name.
- Optional: add GTKWave screenshots next to the script-drawn waveforms.
