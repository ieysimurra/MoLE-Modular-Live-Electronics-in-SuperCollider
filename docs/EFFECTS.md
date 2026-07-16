# Efeitos

O sistema tem **8 categorias**, cada uma com `mix`, `pan`, `bypass`,
roteamento modular e channel routing.

Convenção dos knobs físicos da MIDIMIX por coluna:
- **TOP** = pan
- **MID** = parâmetro principal #1
- **BOT** = parâmetro principal #2
- **Fader** = mix
- **Mute** = bypass

Parâmetros adicionais ficam apenas na GUI.

---

## 1. Time-Stretch
UGen: `Warp1`. Estica/comprime tempo sem alterar pitch.

| Parâmetro | Faixa | Knob |
|---|---|---|
| stretch | 0.25 – 4 | MID |
| windowSize | 0.02 – 1 | BOT |
| overlaps | 1 – 16 | GUI |

## 2. Reverse
UGens: `Latch` + `Sweep` + `BufRd`. Inverte segmentos em tempo real.

| Parâmetro | Faixa | Knob |
|---|---|---|
| segmentDur | 0.1 – 4 s | MID |
| density | 0.25 – 4 | BOT |

## 3. ADSR
UGen: `EnvGen` (Env.adsr). Envelope disparável (gate via RecArm da coluna).

| Parâmetro | Faixa | Knob |
|---|---|---|
| atk | 0.001 – 4 s | MID |
| rel | 0.001 – 8 s | BOT |
| dec / sus | — | GUI |

## 4. Modulation (RM / AM / FM)
Três técnicas selecionáveis pelo dropdown **MODE**.

| Parâmetro | Faixa | Knob |
|---|---|---|
| modFreq | 1 – 5000 Hz (exp) | MID |
| depth | 0 – 1 | BOT |
| ratio | 0.1 – 16 (exp) | GUI |

- **RM** (Ring Modulation): `output = input × sin(modFreq × ratio)`.
  Sons metálicos, bell-like, sidebands puras.
- **AM** (Amplitude Modulation): `output = input × (1 + depth × sin(modFreq × ratio)) × 0.5`.
  Tremolo/sidebands com DC.
- **FM** (Frequency Modulation via delay-line modulada): vibrato em
  depths baixos, sidebands em depths altos.

## 5. Filter + EQ
UGens: `RHPF` + `RLPF` + `BLowShelf` + `BPeakEQ` + `BHiShelf`.

| Parâmetro | Faixa | Knob |
|---|---|---|
| lpfFreq | 50 – 20000 Hz (exp) | MID |
| hpfFreq | 20 – 10000 Hz (exp) | BOT |
| lowGain / midGain / highGain | -24 – 24 dB | GUI |
| lpfRq / hpfRq / midFreq | — | GUI |

## 6. Reverb
UGen: `JPverb` (requer sc3-plugins).

| Parâmetro | Faixa | Knob |
|---|---|---|
| decay (t60) | 0.1 – 30 s (exp) | MID |
| size | 0.5 – 3 | BOT |
| damp | 0 – 1 | GUI |

## 7. Delay
UGens: `LocalIn` / `LocalOut` + `DelayN`. Delay estéreo com feedback.

| Parâmetro | Faixa | Knob |
|---|---|---|
| time | 0.001 – 2 s (exp) | MID |
| feedback | 0 – 0.95 | BOT |

Cuidado com feedback > 0.9 — realimentação quase infinita.

## 8. Harmonizer
8 × `PitchShift` com vozes gated e distribuição estéreo.

| Parâmetro | Faixa | Knob |
|---|---|---|
| voices | 1 – 8 | MID |
| spread | 0 – 12 semitons | BOT |

Cada voz tem deriva de pitch via `LFNoise1` e pan distribuído.

---

## Panorâmica com sinal mono

Efeitos cujo processamento não é essencialmente estéreo (Reverse, ADSR,
Filter, Delay, Reverb) somam os canais (`sum.dup`) antes do `Balance2`,
garantindo pan pleno mesmo com mic mono. O Harmonizer mantém sua
distribuição estéreo interna.
