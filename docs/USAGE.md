# Uso

## Inicialização

```supercollider
// Abra src/main.scd, Ctrl+Enter no parêntese externo
~boot.value;
~cleanup.value;
```

> Ao editar qualquer módulo `.scd`, reexecute `main.scd` inteiro antes de
> `~boot` novamente, para recarregar as definições em memória.

## Fluxos de trabalho típicos

### 1. Improvisação livre com efeitos ao vivo (modo LIVE)

1. Conecte mic/instrumento à interface
2. Solo na MIDIMIX (ou aba Master → LIVE)
3. Aba Efeitos → ative efeitos com Mute (ACTIVE)
4. Ajuste parâmetros pelos knobs físicos ou GUI

### 2. Gravação de loop

1. Aba Loops
2. RecArm coluna N → grava (LED vermelho)
3. Toque pelo tempo desejado (até 60 s)
4. RecArm de novo → para e inicia playback

### 3. Encadeamento de efeitos

1. Aba Efeitos, ative dois ou mais efeitos
2. No segundo, mude o dropdown **SOURCE** para o primeiro
3. Segundo passa a processar a saída do primeiro

### 4. Performance com partitura (música mista)

1. Aba MASTER → seção SCORE inferior
2. Edite as cenas no editor OU LOAD .txt
3. Clique PARSE → lista aparece à direita
4. Durante a performance: Espaço ou botão GO avançam
5. Use Shift+número para saltos não-sequenciais
6. Mensagens `say` grandes orientam o intérprete

Ver [SCORE.md](SCORE.md) para a linguagem completa.

### 5. Salvar e recuperar configurações

1. Configure tudo do jeito que quer
2. Aba Presets → SAVE em um slot
3. Para persistir: nomeie e clique SAVE BANK
4. Em outra sessão: LOAD BANK → LOAD do preset

## Comandos úteis (linha de comando)

```supercollider
// Modo
~setMode.(\live);    // ou \buffer, \off, \both

// Efeitos
~fxBypass.(\reverb, 0);
~fxMix.(\delay, 1.2);
~fxModulationSetMode.(\fm);
~fxModulationSet.(modFreq: 220, depth: 0.6, ratio: 1.5);

// Roteamento
~fxSetSource.(\reverb, \reverse);
~fxResetRouting.value;

// Channel routing
~loopSetCh.(0, \ch1);
~fxSetCh.(\reverb, \ch2);

// Presets / Banks
~presetSave.(0);
~bankSave.("meu_projeto");

// Score
~scoreParse.(text);
~scoreFireScene.(2);
~scoreFireNext.value;

// Diagnóstico
~status.value;
~midiSelfTest.value;
```

## Atalhos de teclado

**Navegação de cenas (score):**
- Espaço / F8 — próxima cena
- Shift+Espaço / F7 — cena anterior
- F5 — dispara selecionada
- Shift+1..9,0 — salto direto para cena N

**Abas e efeitos:**
- Cmd/Ctrl + 1..4 — abas master/samples/loops/effects
- Cmd/Ctrl + 0 — aba presets
- Cmd/Ctrl + 5..9 — foco em colunas de efeitos

**Slots (com foco no view principal):**
- q, w, e, r, t, y, u, i — press-and-hold nos 8 samples
- 1..8 — toggle RecArm nos 8 loops
