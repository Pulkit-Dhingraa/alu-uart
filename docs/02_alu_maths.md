# 2. The Maths Behind My ALU

Every example here uses real values that I ran through my ALU in simulation or checked by hand against the RTL.

## 2.1 Two's complement in 8 bits

An 8-bit pattern can be read in two ways.

| Pattern | Hex | Read as unsigned | Read as signed |
|---|---|---|---|
| `0000_0101` | 05 | 5 | 5 |
| `0111_1111` | 7F | 127 | 127 |
| `1000_0000` | 80 | 128 | −128 |
| `1111_1110` | FE | 254 | −2 |
| `1111_1111` | FF | 255 | −1 |

The hardware does not know which reading I mean. The same adder serves both. Only the **flags** differ: C is for the unsigned reading and V is for the signed reading.

To make a number negative: flip every bit, then add 1.

```math
\boxed{\;-B = \sim\!B + 1\;}
```

Example with B = 3:

```
 B   = 0000_0011
~B   = 1111_1100
~B+1 = 1111_1101 = FD = -3
```

## 2.2 Subtraction is addition

Because −B = ~B + 1:

```math
\boxed{\;A - B = A + \sim\!B + 1\;}
```

This is why my adder has a carry-in. For subtraction I feed it ~B and set the carry-in to 1.

**Example 1: 5 − 3**

```
x   = 0000_0101   (A = 05)
y   = 1111_1100   (~B = FC)
cin =         1
sum = 1_0000_0010   -> result 02, carry-out = 1
```

**Example 2: 3 − 5**

```
x   = 0000_0011   (A = 03)
y   = 1111_1010   (~B = FA)
cin =         1
sum = 0_1111_1110   -> result FE (-2), carry-out = 0
```

## 2.3 Borrow: why I flip the carry on subtraction

Look at the two examples again.

| Subtraction | Carry-out of the adder | Did I need to borrow? |
|---|---|---|
| 5 − 3 | 1 | No |
| 3 − 5 | 0 | Yes |

For a subtraction, a carry-out of 0 means a borrow happened. I want C = 1 to mean "borrow", so I invert it:

```math
\boxed{\;C = \begin{cases} \text{cout} & \text{for additions} \\ \sim\!\text{cout} & \text{for subtractions} \end{cases}\;}
```

This is a design choice. Some processors (ARM, for example) keep the raw carry-out for subtraction instead. I chose the borrow style because "C = 1 means A < B" is easier to read.

## 2.4 Carry versus overflow

- **Carry (C)** tells me the **unsigned** answer did not fit in 8 bits.
- **Overflow (V)** tells me the **signed** answer did not fit in 8 bits.

They are independent. All four combinations happen:

| A + B | Result | Unsigned view | Signed view | C | V |
|---|---|---|---|---|---|
| 05 + 03 | 08 | 5 + 3 = 8, fits | 5 + 3 = 8, fits | 0 | 0 |
| FF + 01 | 00 | 255 + 1 = 256, does not fit | −1 + 1 = 0, fits | 1 | 0 |
| 7F + 01 | 80 | 127 + 1 = 128, fits | 127 + 1 = 128, but 80 reads as −128 | 0 | 1 |
| 80 + 80 | 00 | 128 + 128 = 256, does not fit | −128 + −128 = −256, does not fit | 1 | 1 |

How I detect overflow: adding two numbers of the **same** sign must give that same sign. If the sign of the answer is different, the signed answer did not fit.

```math
\boxed{\;V = (x_7 = y_7)\ \text{and}\ (\text{sum}_7 \neq x_7)\;}
```

Here x and y are the adder inputs **after** the multiplexer, so the same rule works for subtraction (where y is ~B).

Check with 7F + 01: x7 = 0, y7 = 0, sum7 = 1. Same input signs, different answer sign, so V = 1.

## 2.5 Comparing with the adder: SLT and SLTU

To compare A and B, I subtract and look at the flags. I never use the difference itself.

**Unsigned (SLTU):** A < B exactly when A − B needs a borrow.

```math
\boxed{\;\text{SLTU} = \text{borrow of } (A - B)\;}
```

**Signed (SLT):** the sign of A − B says "A is smaller", unless the subtraction overflowed, in which case the sign is wrong and I must flip it.

```math
\boxed{\;\text{SLT} = N \oplus V \quad \text{of } (A - B)\;}
```

**Worked example: A = 80, B = 01.** This pair is useful because the two answers differ.

```
x   = 1000_0000   (A = 80)
y   = 1111_1110   (~B = FE)
cin =         1
sum = 1_0111_1111   -> 7F, carry-out = 1
```

| Flag | Value | Why |
|---|---|---|
| N | 0 | bit 7 of 7F is 0 |
| V | 1 | x7 = 1, y7 = 1, sum7 = 0 |
| borrow | 0 | carry-out was 1 |

- SLT = N xor V = 0 xor 1 = **1**. Correct: −128 < 1.
- SLTU = borrow = **0**. Correct: 128 is not less than 1.

## 2.6 INC, DEC and NEG on the same adder

| Operation | Adder computes | Example | Result | C | V |
|---|---|---|---|---|---|
| INC | A + 00 + 1 | A = FF | 00 | 1 (wrapped past 255) | 0 |
| INC | A + 00 + 1 | A = 7F | 80 | 0 | 1 (127 + 1 does not fit signed) |
| DEC | A + FF + 0 | A = 00 | FF | 1 (borrow) | 0 |
| DEC | A + FF + 0 | A = 80 | 7F | 0 | 1 (−128 − 1 does not fit signed) |
| NEG | 00 + ~A + 1 | A = 05 | FB (−5) | 1 | 0 |
| NEG | 00 + ~A + 1 | A = 80 | 80 | 1 | 1 (+128 does not exist in 8 bits) |

DEC uses FF because FF is −1. Adding −1 is the same as subtracting 1, so I treat its carry as a borrow.

## 2.7 Shifts: catching the bit that falls out

For shifts, C holds the **last bit pushed out**. I catch it by making the value one bit wider before shifting.

**Shift left (SLL), A = 81, B = 1**

```
{0, A}     = 0_1000_0001      9 bits, an empty slot on the left
shift by 1 = 1_0000_0010
              ^ this slot caught the bit that fell out -> C = 1
result     =   0000_0010 = 02
```

**Shift right logical (SRL), A = 81, B = 1**

```
{A, 0}     = 1000_0001_0      9 bits, an empty slot on the right
shift by 1 = 0100_0000_1
                       ^ caught bit -> C = 1
result     = 0100_0000 = 40
```

**Shift right arithmetic (SRA)** is the same, but the empty places on the left are filled with the sign bit, so a negative number stays negative.

```
A = 80 (-128), B = 1  ->  1100_0000 = C0 (-64)
A = 80 (-128), B = 9  ->  1111_1111 = FF (-1), every bit is now the sign bit
```

Large shift amounts: B is a full byte, so it can be more than 7.

| Operation | B from 8 upward gives |
|---|---|
| SLL, SRL | 00 |
| SRA | 00 if A was positive, FF if A was negative |

## 2.8 Rotates

A rotate is a shift where the bit that falls out comes back in on the other side. Nothing is lost. I only use the lowest 3 bits of B, because rotating by 8 brings the byte back to where it started.

```math
\boxed{\;k = B \bmod 8 \qquad \text{ROL} = (A \ll k)\ |\ (A \gg (8-k))\;}
```

**Example: ROL, A = 81, B = 1**

```
A      = 1000_0001
A << 1 = 0000_0010
A >> 7 = 0000_0001     (the bit that wrapped around)
OR     = 0000_0011 = 03,  C = 1 (the wrapped bit)
```

When B = 0, nothing moved, so I force C = 0.
