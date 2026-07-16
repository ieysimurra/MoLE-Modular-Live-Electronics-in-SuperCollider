# Mapeamento MIDI — AKAI MIDIMIX

MIDIMIX tem 8 colunas, cada uma com 3 knobs (TOP/MID/BOT), 1 fader, e
botões Mute e RecArm. Abaixo do master fader: Solo, Bank Left, Bank Right.

O significado dos controles é **contextual à aba ativa**.

## Controles globais

| Controle | Ação |
|---|---|
| Master fader | masterAmp |
| Bank Left / Right | navega: master → samples → loops → effects → presets |
| Solo | alterna modo `\off` ↔ `\live` |

## Aba Efeitos

Coluna = efeito (1=TimeStretch ... 8=Harmonizer).

| Controle | Ação |
|---|---|
| Knob TOP | pan |
| Knob MID | parâmetro principal #1 |
| Knob BOT | parâmetro principal #2 |
| Fader | mix |
| Mute | bypass |
| RecArm (col 3) | dispara envelope do ADSR |

Ver [EFFECTS.md](EFFECTS.md) para o parâmetro de cada knob por efeito.

## Aba Samples

Cada coluna = slot (1–8). Dois estados de interação:

| Controle | Ação |
|---|---|
| Knob TOP | amp |
| Knob MID | rate |
| Knob BOT | pan |
| RecArm | press-and-hold (grava enquanto pressionado) |
| Mute | toggle play/pause do sample gravado |

Após soltar RecArm, sample fica gravado mas silencioso. Só toca ao
apertar Mute. LED do Mute acende enquanto está tocando.

## Aba Loops

| Controle | Ação |
|---|---|
| Knob TOP | amp |
| Knob MID | rate |
| Knob BOT | pan |
| RecArm | ciclo: `empty → grava → para → toca → para → toca...` |
| Mute | stop/play |

Buffer de 60 s. Duração efetiva do loop = tempo entre o 1º e o 2º RecArm.

## Aba Presets

| Controle | Ação |
|---|---|
| Mute (col i) | SAVE preset i |
| RecArm (col i) | LOAD preset i |

## MIDI Learn e diagnóstico

```supercollider
~midiSelfTest.value;
~midiStatus.value;
~reconnectMidi.value;
~midiReset.value;
~midiDebug = true;
```

## Windows (PortMidi)

Feedback de LED para bypass de efeitos vem **desligado** por padrão
(`~midiFxLedEnabled = false`) para evitar instabilidade do PortMidi.
LEDs de slots e presets continuam ativos. Para reativar:

```supercollider
~midiFxLedEnabled = true;
```
