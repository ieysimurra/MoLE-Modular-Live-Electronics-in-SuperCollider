# Arquitetura de áudio

## Fluxo de sinal

```
                    ┌─────────────────────────────────────┐
   Mic / Linha ─────► inputStage ──► micBus                │
   (Focusrite)      └─────────────────────────────────────┘
                                       │
   Loops/Samples ──► sourceBus ────────┤
   (FX route)                          │
                                       ▼
                          ┌────────────────────────┐
                          │  fxGroup (8 efeitos)    │
                          │  cada efeito:           │
                          │   • lê de inBus + mic   │
                          │   • escreve em:         │
                          │      - outBus próprio   │──► (encadeamento)
                          │      - masterBus (fxBus)│──┐
                          └────────────────────────┘   │
                                                        │
   Loops/Samples ──► rawBus ─────────────────────────► │ (dry sem efeitos)
   (RAW route)                                          │
                                                        ▼
                          ┌────────────────────────┐
                          │  masterStage            │
                          │   XFade2(rawBus, fxBus) │◄── wetDry
                          │   × masterAmp           │
                          └────────────────────────┘
                                       │
                                       ▼
                                   Saída (0,1)

  Independente:
   Mic/Linha ────► SoundIn.ar ──► sampleRecorder ──► buffers[\samples]
   (gravação direta, não passa pelo master)
```

## Buses

| Bus | Canais | Função |
|---|---|---|
| `~buses[\source]` | 2 | Entrada dos efeitos (loops/samples com rota FX) |
| `~buses[\mic]` | 2 | Sinal do microfone |
| `~buses[\fx]` | 2 | Saída acumulada dos efeitos → master |
| `~buses[\raw]` | 2 | Sinal seco (RAW) → master |
| `~buses[\fxOut][<efeito>]` | 2 | Saída **individual** de cada efeito (encadeamento) |

`sourceBus` é exclusivamente a *entrada* dos efeitos. Sinal seco vai pelo
`rawBus`. Essa separação evita vazamento no modo "só FX".

## Grupos (ordem de execução)

```
inputGroup → captureGroup → playbackGroup → fxGroup → masterGroup
```

Dentro de `fxGroup`, a ordem é recalculada dinamicamente (ordenação
topológica) quando há encadeamento — efeito-fonte roda antes do
efeito-destino, sem latência de 1 bloco.

## Gravação de samples: caminho paralelo

O SynthDef `\sampleRecorder` lê **direto do `SoundIn.ar`**, não do `micBus`.
Isso significa que a gravação é **independente do master** — gravar em
`mode off` funciona e mantém o sistema silencioso (útil para captura de
gestos do intérprete sem amplificação).

## Roteamento modular dos efeitos

Cada efeito tem:

- `inBus` — de onde lê (`sourceBus` ou `outBus` de outro efeito)
- `micBus` — mic, somado se `includeMic = 1`
- `outBus` — saída individual (sempre escrita)
- `masterBus` — barramento geral, escrito condicionalmente a `sendToMaster`

Quando `source` muda de `dry` para outro efeito, `includeMic` vai a 0
automaticamente — o mic já foi incorporado no efeito anterior.

Ver [ROUTING.md](ROUTING.md).

## Modos de operação

- **OFF** — silêncio no master (mas mic continua ativo para gravação)
- **LIVE** — processa mic em tempo real
- **BUFFER** — reproduz loops/samples gravados
- **BOTH** — combina LIVE + BUFFER

## Estado em sclang

Espelhado em sclang para evitar consultas assíncronas ao servidor:

- `~fxBypassState`, `~fxParamState`, `~fxRouting`
- `~sampleSlots`, `~loopSlots`

## Ciclo de vida dos Synths de sample

SynthDef `\sampleVoice` tem dois envelopes:

- **doneEnv** — chega em zero ao fim do buffer, `doneAction: 2`
- **gateEnv** — release curto quando `gate = 0`, `doneAction: 2`

O primeiro a atingir zero libera o Synth. `NodeWatcher.onFree` notifica
sclang para atualizar GUI e MIDI.

## Cancelamento cooperativo (score)

O motor de partitura usa Routines com `.wait` para operações assíncronas.
Rotinas são canceladas **sem `.stop`** — usa-se um **run-id** global
(`~scoreCurrentRunId`) que é incrementado a cada nova cena. Routines
antigas verificam entre comandos e saem via `break`.

Isso evita `_RoutineResume` que `.stop` em Routines com waits pendentes
causa no AppClock. O mesmo padrão é aplicado aos fades (`~scoreFadeGen`).
