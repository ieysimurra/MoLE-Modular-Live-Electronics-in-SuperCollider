# Changelog

Todas as mudanças notáveis deste projeto estão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
e o projeto adere ao [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [1.1.0] — 2026-06

### Adicionado
- **Sistema de partitura em cue list** (`src/score.scd`, aba MASTER)
  - Formato `.txt` com blocos `[Cena N: descrição]` e múltiplos comandos por cena
  - Cabeçalhos `title:`, `composer:`, `description:`
  - Comandos: `mode`, `preset`, `bank`, `fx.bypass/mix/param/source/master`,
    `sample.rec/stop/play/pause`, `loop.rec/play/stop`, `master.amp`, `wetdry`,
    `inputgain`, `say`
  - Fades opcionais (`fade N`)
  - Editor multi-linha embutido na GUI + carga de arquivo externo
  - Lista de cenas com destaque da atual (laranja)
  - Botões PREV / GO / NEXT / RESET
  - Mensagens `say` em texto grande para o intérprete
  - Persistência em `scores/` dentro do projeto (versionável)
- **Efeito Modulation** com três modos (RM/AM/FM), substituindo Cross-Synth
- **Detecção de fim natural do sample** — playBtn atualiza automaticamente
- **Atalhos de teclado do score**: F5/F7/F8, Shift+1..9,0
- Documentação `docs/SCORE.md`
- Partitura de referência: **Wabi-sabi** (Ivan Simurra), obra estreia com o sistema

### Corrigido
- **Panorâmica com sinal mono**: `sum.dup` antes do `Balance2` em Reverse, ADSR,
  Filter, Delay e Reverb
- **Sample não processava por efeitos**: bug de roteamento (`\outFxBus`/`\outRawBus`)
- **Auto-play indesejado do sample**: comportamento tipo pad sampler agora
  (RecArm grava silencioso, Mute dispara playback)
- **Loops**: duração manual via gate (1º RecArm inicia, 2º para)
- **Buffer padrão dos loops**: 60 s por slot
- **Ganho do Harmonizer** aumentado
- **Diretório de scores/banks** movido para dentro do projeto (portável)
- **Cor do texto no editor após LOAD** (reset pelo Qt/Windows)
- **Símbolos com ponto em SC**: `\fx.bypass` → `'fx.bypass'` (interpretação correta)
- **Método `hiliteColor_`** em ListView (não `hilightColor_`)
- **`sample.stop` inteligente**: detecta estado — para gravação se estava
  gravando, ou pausa playback se estava tocando

### Cancelamento cooperativo (padrão run-id)
- Substituído todo `.stop` em Routine com waits pendentes por padrão de
  cancelamento cooperativo via generation counter, eliminando erros
  `_RoutineResume` no AppClock
- Aplicado ao motor de cenas (`~scoreFireScene`), fades (`~scoreFade`) e
  reset (`~scoreReset`)
- Try/catch em `~scoreExecuteCommand` isola erros de comandos individuais

### Mudanças internas
- Nomenclatura `crossSynth` → `modulation` (presets antigos ignorados
  graciosamente)
- SynthDef `\sampleVoice` com controle de gate para stop suave;
  `doneAction: 2` nos dois envelopes garante liberação correta
- Foco de teclado: widgets Editor, ListView e botões têm handlers próprios
  de score, independente de onde está o foco
- Atalhos numéricos usam `keycode` físico (independente de layout ABNT2/US)

## [1.0.0] — 2026-05

### Adicionado
- **8 categorias de efeitos**: Time-Stretch, Reverse, ADSR, Cross-Synth,
  Filter+EQ, Reverb (JPverb), Delay, Harmonizer
- **Roteamento modular de efeitos** com source picker, detecção de ciclos,
  ordenação topológica
- **Channel routing** (CH1/CH2/Stereo) por slot e por efeito
- **Looping** de até 60 s com overdub e fades
- **Sampling** press-and-release
- **Sistema de presets** — 8 em memória + persistência em banks `.preset`
- **Controle MIDI** completo da AKAI MIDIMIX
- **GUI** com 5 abas
- Toggle `→ MASTER` por efeito

[1.1.0]: https://github.com/<seu-usuario>/live-electronics-sc/releases/tag/v1.1.0
[1.0.0]: https://github.com/<seu-usuario>/live-electronics-sc/releases/tag/v1.0.0
