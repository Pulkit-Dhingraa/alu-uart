"""Draws the waveform pictures in docs/img from build/waves.vcd (made by tb/tb_waves.v).

Usage (from the repository root):
    iverilog -g2012 -o build/sim_waves.vvp tb/tb_waves.v rtl/*.v
    vvp -n build/sim_waves.vvp
    python3 scripts/plot_waves.py
"""
import re
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

VCD = "build/waves.vcd"
INK, GRID, ACCENT = "#1f2933", "#d0d7de", "#c2410c"


def read_vcd(path):
    names, sig, t = {}, {}, 0
    for line in open(path):
        line = line.strip()
        m = re.match(r"\$var \w+ (\d+) (\S+) (\S+)", line)
        if m:
            names[m.group(2)] = m.group(3)
            sig.setdefault(m.group(3), [])
        elif line.startswith("#"):
            t = int(line[1:])                      # picoseconds
        elif line and line[0] in "01xz" and line[1:] in names:
            sig[names[line[1:]]].append((t, 0 if line[0] in "xz" else int(line[0])))
        elif line and line[0] == "b":
            val, code = line[1:].split()
            if code in names:
                sig[names[code]].append((t, int(val, 2) if set(val) <= {"0", "1"} else 0))
    return sig, t


def steps(changes, t0, t1):
    """Turn a change list into x/y points for a square wave between t0 and t1 (ps)."""
    xs, ys, cur = [t0], [0], 0
    for t, v in changes:
        if t <= t0:
            cur = v
            ys[0] = v
        elif t <= t1:
            xs += [t, t]
            ys += [cur, v]
            cur = v
    xs.append(t1)
    ys.append(cur)
    return xs, ys


def draw_bit(ax, row, label, changes, t0, t1, unit, color=INK):
    xs, ys = steps(changes, t0, t1)
    ax.plot([(x - t0) / unit for x in xs], [row + 0.7 * y for y in ys], color=color, lw=1.3)
    ax.text(-0.01, row + 0.35, label, transform=ax.get_yaxis_transform(),
            ha="right", va="center", fontsize=10, color=INK, family="monospace")


def draw_bus(ax, row, label, changes, t0, t1, unit, fmt):
    pts = [(t0, 0)]
    for t, v in changes:
        if t <= t0:
            pts[0] = (t0, v)
        elif t <= t1:
            pts.append((t, v))
    pts.append((t1, None))
    for (ta, v), (tb, _) in zip(pts, pts[1:]):
        a, b = (ta - t0) / unit, (tb - t0) / unit
        ax.fill_between([a, b], row, row + 0.7, facecolor="#f6f8fa", edgecolor=INK, lw=0.9)
        if (b - a) > 0.035 * (t1 - t0) / unit:
            ax.text((a + b) / 2, row + 0.35, fmt(v), ha="center", va="center",
                    fontsize=9, color=INK, family="monospace")
    ax.text(-0.01, row + 0.35, label, transform=ax.get_yaxis_transform(),
            ha="right", va="center", fontsize=10, color=INK, family="monospace")


def finish(ax, nrows, xlabel, title, path):
    ax.set_ylim(-0.3, nrows + 0.1)
    ax.set_yticks([])
    ax.set_xlabel(xlabel, fontsize=10, color=INK)
    ax.set_title(title, fontsize=11, color=INK, loc="left")
    ax.grid(axis="x", color=GRID, lw=0.6)
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.margins(x=0)
    plt.tight_layout()
    plt.savefig(path, dpi=150, facecolor="white")
    plt.close()
    print("wrote", path)


sig, t_end = read_vcd(VCD)
US, NS = 1_000_000, 1_000                       # ps per microsecond / nanosecond
RX = {0: "HUNT", 1: "GET_A", 2: "GET_B", 3: "GET_OP"}
TX = {0: "TX_IDLE", 1: "SEND_R", 2: "SEND_S"}
hx = lambda v: "%02X" % v

first_fall = next(t for t, v in sig["line"] if v == 0 and t > 0)
calc_t = next(t for t, v in sig["calc"] if v == 1)

# ---- picture 1: the whole round trip -------------------------------------------------
t0, t1 = first_fall - 10 * US, calc_t + 200 * US
fig, ax = plt.subplots(figsize=(12, 5.2))
rows = [("uart_rxd", "line", "bit"), ("rx_valid", "rx_valid", "bit"), ("rx_data", "rx_data", hx),
        ("rx_state", "rx_state", lambda v: RX[v]), ("calc", "calc", "bit"),
        ("alu_result", "alu_result", hx), ("tx_state", "tx_state", lambda v: TX[v]),
        ("tx_busy", "tx_busy", "bit"), ("uart_txd", "txd", "bit")]
for i, (label, key, kind) in enumerate(rows):
    row = len(rows) - 1 - i
    if kind == "bit":
        draw_bit(ax, row, label, sig[key], t0, t1, US, ACCENT if key in ("line", "txd") else INK)
    else:
        draw_bus(ax, row, label, sig[key], t0, t1, US, kind)
finish(ax, len(rows), "time (microseconds)",
       "Request [A5 05 03 00] in, reply [08 00] out  (simulation: tb/tb_waves.v)",
       "docs/img/wave_roundtrip.png")

# ---- picture 2: one frame, with the receiver's sampling points ------------------------
t0, t1 = first_fall - 6 * US, first_fall + 94 * US
fig, ax = plt.subplots(figsize=(12, 2.9))
draw_bit(ax, 1, "uart_rxd", sig["line"], t0, t1, US, ACCENT)
draw_bit(ax, 0, "rx_valid", sig["rx_valid"], t0, t1, US)
samples = [t for t, v in sig["rx_sample"] if v == 1 and t0 < t < t1]
names = ["start"] + ["d%d" % i for i in range(8)] + ["stop"]
for t, nm in zip(samples, names):
    x = (t - t0) / US
    ax.plot([x, x], [0.95, 1.85], color=INK, lw=0.8, ls=":")
    ax.plot([x], [1.9], marker="v", color=INK, ms=5)
    ax.text(x, 2.05, nm, ha="center", va="bottom", fontsize=9, color=INK)
finish(ax, 2.4, "time (microseconds)",
       "Byte A5 on the wire. Triangles = the moments uart_rx samples the line",
       "docs/img/wave_frame_a5.png")

# ---- picture 3: from the last request byte to the reply's start bit -------------------
last_rxv = [t for t, v in sig["rx_valid"] if v == 1][3]
t0, t1 = last_rxv - 30 * NS, last_rxv + 620 * NS
fig, ax = plt.subplots(figsize=(12, 4.2))
rows = [("clk", "clk"), ("tick16", "tick16"), ("rx_valid", "rx_valid"), ("calc", "calc"),
        ("tx_start", "tx_start"), ("tx_busy", "tx_busy"), ("uart_txd", "txd")]
for i, (label, key) in enumerate(rows):
    draw_bit(ax, len(rows) - 1 - i, label, sig[key], t0, t1, NS, ACCENT if key == "txd" else INK)
finish(ax, len(rows), "time (nanoseconds, 10 ns = 1 clock)",
       "Reply latency: rx_valid of the op byte -> start bit of the reply",
       "docs/img/wave_latency.png")
