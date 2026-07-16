# Roteamento modular e channel routing

## Source picker — encadeamento

Cada efeito tem um seletor **SOURCE** no topo da coluna:

- `dry` (padrão) — sinal seco do `sourceBus` + mic
- `timeStretch`, `reverse`, `adsr`, `modulation`, `filter`, `reverb`,
  `delay`, `harmonizer` — a saída individual de outro efeito

Permite topologias em **série**, **paralelo** ou **mistas**.

### Toggle "→ MASTER"

Cada efeito tem um botão `→ MASTER` (padrão: ligado). Quando desligado,
o efeito não vai ao mix final — útil quando é apenas um estágio
intermediário de uma cadeia.

### Detecção de ciclos

Ao mudar um source, o sistema verifica se criaria um ciclo (A→B→A). Se
sim, recusa a mudança e imprime aviso.

### Ordem de execução

A cada mudança de source, a ordem dos synths no servidor é recalculada
por **ordenação topológica** — efeito-fonte roda antes do efeito-destino,
sem latência de 1 bloco.

### Exemplos

**Série pura:**
```
Reverse (source: dry) → Reverb (source: reverse) → TimeStretch (source: reverb)
```

**Série + paralelo:**
```
Reverse (source: dry, → master)
Reverb  (source: reverse, → master)
Filter  (source: dry, → master)         ← rota paralela seca-filtrada
```

**Via código:**
```supercollider
~fxSetSource.(\reverb, \reverse);
~fxSetSendToMaster.(\reverse, false);
~fxResetRouting.value;
```

**Via score:**
```
[Cena N: cadeia complexa]
fx.source reverb reverse
fx.master reverse off
fx.mix reverb 1.0 fade 2
```

## Channel routing — CH1 / CH2 / Stereo

Permite isolar entradas da interface (mic vocal no canal 1, instrumento
de linha no canal 2).

### Nos slots

Botão `STEREO` / `CH1` / `CH2` por slot. Aplica-se à **próxima gravação**.

```supercollider
~loopSetCh.(0, \ch1);
~sampleSetCh.(3, \ch2);
~loopCycleCh.(0);
```

### Nos efeitos

Botão `IN: STEREO` / `CH1` / `CH2` por efeito.

```supercollider
~fxSetCh.(\reverb, \ch2);   // reverb processa só ch2 do mic
```

O channel routing dos efeitos afeta apenas o sinal do `micBus`. O sinal
vindo de `inBus` (loops/samples ou cadeia de efeitos) passa sem alteração.

## Persistência

Todo o roteamento (source, → master, channel) é capturado em presets e
banks. Cada projeto pode ter sua topologia salva.
