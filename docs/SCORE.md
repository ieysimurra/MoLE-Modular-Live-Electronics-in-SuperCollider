# SCORE — Cue List

Sistema de partitura em **cue list**: uma lista de cenas pré-configuradas
disparadas manualmente. Cada cena é um estado do sistema. **Não há
relógio automático** — você controla o andamento, saltando entre cenas
na ordem que quiser.

Ideal para música mista instrumental, onde a eletrônica deve responder ao
andamento do intérprete acústico.

## Formato

```
title:       nome da peça          # opcional
composer:    autor                 # opcional
description: descrição livre       # opcional

[Cena 1: nome]
comando1
comando2

[Cena 2: outro nome]
comando3
comando4

# Comentários começam com #
```

### Regras

- Cena começa com `[nome]` ou `[Cena N: descrição]`
- Comandos abaixo pertencem à cena até a próxima `[...]`
- Executados **na ordem** em que aparecem
- Linhas em branco e comentários (`#`) ignorados

## Comandos

### Modo do sistema
| Comando | Ação |
|---|---|
| `mode off\|live\|buffer\|both` | modo global |

### Presets e Banks
| Comando | Ação |
|---|---|
| `preset <n>` | carrega preset (0-7) |
| `bank <nome>` | carrega bank persistente |

### Efeitos
| Comando | Ação |
|---|---|
| `fx.bypass <fx> on\|off` | on = ativo, off = bypass |
| `fx.mix <fx> <valor>` | mix (0-2) |
| `fx.param <fx> <param> <valor>` | qualquer parâmetro |
| `fx.source <fx> <source>` | encadeamento (dry ou nome de efeito) |
| `fx.master <fx> on\|off` | envio ao master |

Efeitos: `timeStretch`, `reverse`, `adsr`, `modulation`, `filter`,
`reverb`, `delay`, `harmonizer`.

### Samples e Loops
| Comando | Ação |
|---|---|
| `sample.rec <n>` | inicia gravação |
| `sample.stop <n>` | inteligente: para gravação **ou** playback conforme estado |
| `sample.play <n>` | dispara playback |
| `sample.pause <n>` | pausa playback (alias explícito) |
| `loop.rec <n>` | toggle gravação/stop |
| `loop.play <n>` | inicia playback |
| `loop.stop <n>` | para playback |

### Globais
| Comando | Ação |
|---|---|
| `master.amp <valor>` | volume master (0-1) |
| `wetdry <valor>` | crossfade wet/dry |
| `inputgain <valor>` | ganho de entrada |

### Mensagens
| Comando | Ação |
|---|---|
| `say <texto...>` | mensagem grande na GUI para o intérprete |

## Fades opcionais

Qualquer comando com valor numérico aceita `fade <segundos>`:

```
fx.mix reverb 0.9 fade 3
master.amp 0.3 fade 8
fx.param harmonizer spread 8 fade 5
```

Interpolação a ~30 fps. Ao disparar uma nova cena, fades anteriores são
cancelados para evitar conflitos.

## Gravação silenciosa

O SynthDef de gravação (`\sampleRecorder`) lê **direto do hardware**,
não passa pelo master. Use `mode off` durante cenas de gravação para
capturar o gesto do intérprete **sem amplificação**:

```
[Cena 2: Grava gesto A]
mode off              # PA silente, mas gravação continua
sample.rec 0
say Gravando gesto A em silêncio
```

Isso é o padrão idiomático para música mista: o intérprete se ouve
acusticamente (pelo próprio instrumento), o sistema grava sem
interferência, e na próxima cena devolve o gesto processado.

## Interface (aba MASTER)

- **Editor** multi-linha (esquerda)
- **Lista de cenas** (direita) — clique seleciona, duplo-clique dispara
- Botões: LOAD .txt, SAVE .txt, ↻ (atualizar), PARSE
- **Transport**: `◀ PREV`, `▶ GO`, `NEXT ▶`, `⟲ RESET`
- Cena atual destacada em laranja
- Mensagem `say` grande e amarela

Arquivos ficam em `scores/` dentro do projeto.

## Atalhos de teclado

Com a janela em foco:

| Tecla | Ação |
|---|---|
| **Espaço** | Próxima cena |
| **Shift + Espaço** | Cena anterior |
| **F8** | Próxima cena |
| **F7** | Cena anterior |
| **F5** | Dispara selecionada |
| **Shift + 1..9** | Salto direto para cena 1..9 |
| **Shift + 0** | Cena 10 |
| **Enter** (na lista) | Dispara selecionada |
| **Backspace** (na lista) | Cena anterior |

Os atalhos numéricos usam **keycode físico** — independente de layout
(ABNT2, US, etc.).

## API para uso avançado

```supercollider
~scoreParse.(text);
~scoreFireScene.(0);
~scoreFireNext.value;
~scoreFirePrev.value;
~scoreReset.value;

~scoreScenes;             // lista parseada
~scoreCurrentIdx;         // índice atual
~scoreCurrentScene.value;

~scoreLoadFile.("wabi-sabi");
~scoreSaveFile.("wabi-sabi", text);
~scoreList.value;
```

## Filosofia colaborativa

Você pode ajustar controles manualmente pela GUI, MIDI ou linha de comando
a qualquer momento. Quando você dispara a próxima cena, os comandos dela
sobrescrevem seus ajustes. Não há bloqueio.

**Recomendação:** presets para estados reutilizáveis, banks para conjuntos
de projetos, cue list para a estrutura formal da peça.
