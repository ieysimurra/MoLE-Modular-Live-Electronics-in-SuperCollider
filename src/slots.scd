// =====================================================================
// LIVE ELECTRONICS — slots.scd
// =====================================================================
// Estado e funções de controle dos 8 samples e 8 loops.
// Define ~initSlots, ~installOSCdefs, e todas as funções de captura.
//
// ROTEAMENTO POR SLOT (\route):
//   \fx   — passa pelos efeitos (sourceBus). Default.
//   \raw  — vai direto ao master (rawBus), sem efeitos.
//   \both — toca em ambos os caminhos simultaneamente.
//
// Hooks de GUI/MIDI:
//   • Após cada mudança de estado de slot, chama ~onSlotStateChanged se
//     definido (gui.scd/midi.scd registram callbacks aí).
//   • Após mudança de roteamento, chama ~onSlotRouteChanged.
// =====================================================================


// Helper: converte modo de roteamento em par (sendFx, sendRaw).
~routeAmps = { |route|
    case
    { route == \fx }   { [1, 0] }
    { route == \raw }  { [0, 1] }
    { route == \both } { [1, 1] }
    { [1, 0] };  // default: fx
};


~initSlots = {
    ~sampleSlots = Array.fill(8, {
        IdentityDictionary[
            \state -> \empty, \frames -> 0,
            \recSynth -> nil, \playSynth -> nil,
            \route -> \fx, \inputCh -> \stereo
        ]
    });
    ~loopSlots = Array.fill(8, {
        IdentityDictionary[
            \state -> \empty, \frames -> 0, \dur -> 30, \synth -> nil,
            \route -> \fx, \recStartTime -> nil, \inputCh -> \stereo
        ]
    });
};


// Helper interno: notifica listeners de mudança de estado
~notifySlotChange = { |kind, idx, newState|
    ~onSlotStateChanged !? { |fn| fn.value(kind, idx, newState) };
};


// =====================================================================
//   OSC CALLBACKS
// =====================================================================
~installOSCdefs = {

    OSCdef(\sampleRecorded, { |msg|
        var slotId, frames, slot, buf, newState;
        slotId = msg[3].asInteger;
        frames = msg[4].asInteger;
        if(slotId < 0 or: { slotId >= 8 }) { ^nil };
        slot = ~sampleSlots[slotId];
        buf  = ~buffers[\samples][slotId];

        slot[\frames]   = frames;
        slot[\recSynth] = nil;
        slot[\playSynth] = nil;

        // Se gravou algo audível, fica em \recorded (aguardando Mute
        // para tocar). Se não gravou nada útil, volta a \empty.
        newState = if(frames > 1000) { \recorded } { \empty };
        slot[\state] = newState;

        ("Sample [" ++ slotId ++ "] gravado: " ++ frames ++ " frames ("
         ++ (frames / s.sampleRate).round(0.01) ++ "s) → " ++ newState).postln;

        ~notifySlotChange.(\sample, slotId, newState);
    }, '/sampleRecorded');

    OSCdef(\loopRecorded, { |msg|
        var slotId, frames, slot, buf;
        slotId = msg[3].asInteger;
        frames = msg[4].asInteger;
        if(slotId < 0 or: { slotId >= 8 }) { ^nil };
        slot = ~loopSlots[slotId];
        buf  = ~buffers[\loops][slotId];

        slot[\frames] = frames;
        // NÃO inicia playback automaticamente. Fica em \stopped, com
        // o áudio já gravado pronto para ser disparado por ~loopPlay
        // (botão MUTE na GUI/MIDIMIX).
        slot[\state]  = \stopped;
        slot[\synth]  = nil;

        ("Loop [" ++ slotId ++ "] gravado ("
         ++ (frames / s.sampleRate).round(0.01) ++ "s). "
         ++ "Pressione MUTE para reproduzir.").postln;

        ~notifySlotChange.(\loop, slotId, \stopped);
    }, '/loopRecorded');
};


// =====================================================================
//   SAMPLES — press-and-release
// =====================================================================
~samplePress = { |idx|
    var slot, buf;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~sampleSlots[idx];
    if(slot[\state] == \recording) { ^nil };

    // Se estiver tocando (playing), pare primeiro — o Press vai regravar sobre.
    if(slot[\playSynth].notNil) {
        slot[\playSynth].set(\gate, 0);
        slot[\playSynth] = nil;
    };

    if(slot[\recSynth].notNil) { slot[\recSynth].free; slot[\recSynth] = nil };
    buf = ~buffers[\samples][idx];
    buf.zero;
    slot[\frames] = 0;
    slot[\state]  = \recording;
    slot[\recSynth] = Synth(\sampleRecorder, [
        \inBus, 0, \bufnum, buf.bufnum, \gate, 1, \slotId, idx,
        \chMode, ~chModeToInt.(slot[\inputCh] ? \stereo)
    ], ~groups[\capture]);
    ("Sample [" ++ idx ++ "] gravando...").postln;
    ~notifySlotChange.(\sample, idx, \recording);
};

~sampleRelease = { |idx|
    var slot;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~sampleSlots[idx];
    if(slot[\state] != \recording) { ^nil };
    slot[\recSynth].set(\gate, 0);
    slot[\state] = \stopping;
    ~notifySlotChange.(\sample, idx, \stopping);
};

// Toca o sample gravado. Respeita ~sampleSlots[idx][\route] (fx/raw/both)
// e usa os buses corretos, garantindo que a chain de efeitos seja aplicada.
~samplePlay = { |idx|
    var slot, buf, amps;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~sampleSlots[idx];
    if(slot[\frames] == 0) { ("Sample [" ++ idx ++ "] vazio").postln; ^nil };
    // Já está tocando (ou tinha uma referência zombie): re-trigger.
    // Envolve em try para não quebrar se a referência ficar inválida
    // (Synth já liberado no servidor mas sclang ainda com o handle).
    if(slot[\playSynth].notNil) {
        try {
            slot[\playSynth].set(\gate, 0);
        } { |err|
            ("Sample [" ++ idx ++ "] referência zombie ignorada: "
              ++ err.errorString).postln;
        };
        slot[\playSynth] = nil;
    };
    buf = ~buffers[\samples][idx];
    amps = ~routeAmps.(slot[\route] ? \fx);
    slot[\playSynth] = Synth(\sampleVoice, [
        \bufnum,    buf.bufnum,
        \outFxBus,  ~buses[\source].index,
        \outRawBus, ~buses[\raw].index,
        \durFrames, slot[\frames],
        \amp, 1.0, \rate, 1.0, \pan, 0,
        \gate, 1,
        \sendFx, amps[0], \sendRaw, amps[1]
    ], ~groups[\playback]);
    slot[\state] = \playing;
    // Quando o Synth libera sozinho (fim natural do sample), precisa
    // notificar sclang para atualizar estado e GUI. Capturamos a
    // referência local para comparar depois (evita race condition
    // se o usuário disparar outro playback antes deste terminar).
    block { |break|
        var thisSynth = slot[\playSynth];
        NodeWatcher.register(thisSynth);
        thisSynth.onFree({
            defer {
                if(slot[\playSynth] == thisSynth) {
                    slot[\playSynth] = nil;
                    if(slot[\state] == \playing) {
                        slot[\state] = \recorded;
                        ~notifySlotChange.(\sample, idx, \recorded);
                    };
                };
            };
        });
    };
    ("Sample [" ++ idx ++ "] tocando (route=" ++ slot[\route] ++ ").").postln;
    ~notifySlotChange.(\sample, idx, \playing);
};

// Pausa (interrompe playback com pequeno release para evitar clique).
// O buffer permanece — próximo ~samplePlay recomeça do início.
~sampleStop = { |idx|
    var slot;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~sampleSlots[idx];
    if(slot[\playSynth].notNil) {
        try {
            slot[\playSynth].set(\gate, 0);
        } { |err|
            ("Sample [" ++ idx ++ "] set gate ignorado (zombie): "
              ++ err.errorString).postln;
        };
        slot[\playSynth] = nil;
        slot[\state] = \recorded;
        ("Sample [" ++ idx ++ "] pausado.").postln;
        ~notifySlotChange.(\sample, idx, \recorded);
    };
};

// Toggle usado pelo Mute (MIDI) e pela GUI: se tocando → para; senão → toca.
~sampleToggle = { |idx|
    var slot;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~sampleSlots[idx];
    case
    { slot[\state] == \playing }  { ~sampleStop.(idx) }
    { slot[\state] == \recorded } { ~samplePlay.(idx) }
    { slot[\state] == \empty }    { ("Sample [" ++ idx ++ "] vazio — nada a tocar").postln };
};


// =====================================================================
//   LOOPS
// =====================================================================
~loopSetDur = { |idx, dur = 4|
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    ~loopSlots[idx][\dur] = dur.max(0.1);
    ("Loop [" ++ idx ++ "] duração configurada: " ++ dur ++ "s").postln;
};

// Inicia gravação em modo manual: gate=1 até ser parado por ~loopStopRecord.
// O parâmetro `dur` agora é apenas o LIMITE máximo de segurança (default = 60s,
// que coincide com o tamanho do buffer). A duração efetiva do loop será o
// tempo entre ~loopRecord e ~loopStopRecord.
~loopRecord = { |idx, dur|
    var slot, buf, maxDur;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~loopSlots[idx];
    if(slot[\synth].notNil) { slot[\synth].free; slot[\synth] = nil };
    buf = ~buffers[\loops][idx];
    buf.zero;
    // maxDur = duração do buffer (segurança contra wrap)
    maxDur = (buf.numFrames / s.sampleRate) - 0.1;
    dur = dur ? maxDur;
    slot[\dur] = dur;
    slot[\frames] = 0;
    slot[\state] = \recording;
    slot[\recStartTime] = SystemClock.seconds;
    slot[\synth] = Synth(\loopRecorder, [
        \inBus, 0, \bufnum, buf.bufnum, \slotId, idx,
        \gate, 1, \maxDur, maxDur,
        \chMode, ~chModeToInt.(slot[\inputCh] ? \stereo)
    ], ~groups[\capture]);
    ("Loop [" ++ idx ++ "] gravando (aperte REC ARM novamente para parar; "
     ++ "máx " ++ maxDur.round(0.1) ++ "s)...").postln;
    ~notifySlotChange.(\loop, idx, \recording);
};

// Para a gravação manual: envia gate=0, o envelope faz release de 5ms
// e o OSC /loopRecorded é disparado com a posição final, que vira a
// duração efetiva do loop em frames.
~loopStopRecord = { |idx|
    var slot, elapsed;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~loopSlots[idx];
    if(slot[\state] != \recording) { ^nil };
    if(slot[\synth].notNil) {
        slot[\synth].set(\gate, 0);
        // não liberamos a synth aqui; ela auto-libera após o release
        // do envelope (TDelay no SynthDef), depois do SendReply
    };
    elapsed = SystemClock.seconds - (slot[\recStartTime] ? SystemClock.seconds);
    ("Loop [" ++ idx ++ "] gravação parada após "
     ++ elapsed.round(0.01) ++ "s. Standby — pressione MUTE para reproduzir.").postln;
    // a transição para \stopped acontece no callback /loopRecorded
};

~loopStop = { |idx|
    var slot;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~loopSlots[idx];
    if(slot[\synth].notNil) {
        slot[\synth].set(\gate, 0);
        slot[\synth] = nil;
        slot[\state] = \stopped;
        ("Loop [" ++ idx ++ "] pausado.").postln;
        ~notifySlotChange.(\loop, idx, \stopped);
    };
};

~loopPlay = { |idx|
    var slot, buf, amps;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~loopSlots[idx];
    if(slot[\frames] == 0)  { ("Loop [" ++ idx ++ "] vazio").postln; ^nil };
    if(slot[\synth].notNil) { ^nil };
    buf = ~buffers[\loops][idx];
    amps = ~routeAmps.(slot[\route]);
    slot[\synth] = Synth(\loopVoice, [
        \bufnum, buf.bufnum,
        \outFxBus,  ~buses[\source].index,
        \outRawBus, ~buses[\raw].index,
        \inBus, 0,
        \loopFrames, slot[\frames],
        \rate, 1, \amp, 1.0, \pan, 0,
        \gate, 1, \dubAmt, 0, \feedback, 1,
        \sendFx, amps[0], \sendRaw, amps[1]
    ], ~groups[\playback]);
    slot[\state] = \playing;
    ("Loop [" ++ idx ++ "] tocando.").postln;
    ~notifySlotChange.(\loop, idx, \playing);
};

~loopOverdub = { |idx, feedback = 1|
    var slot, newDub, newState;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~loopSlots[idx];
    if(slot[\synth].isNil) { ^nil };
    newDub = if(slot[\state] == \overdubbing) { 0 } { 1 };
    newState = if(newDub > 0) { \overdubbing } { \playing };
    slot[\synth].set(\dubAmt, newDub, \feedback, feedback);
    slot[\state] = newState;
    ("Loop [" ++ idx ++ "] " ++ if(newDub > 0) { "OVERDUB ON" } { "overdub off" }).postln;
    ~notifySlotChange.(\loop, idx, newState);
};

~loopClear = { |idx|
    var slot;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~loopSlots[idx];
    if(slot[\synth].notNil) { slot[\synth].free; slot[\synth] = nil };
    ~buffers[\loops][idx].zero;
    slot[\state] = \empty;
    slot[\frames] = 0;
    ("Loop [" ++ idx ++ "] limpo.").postln;
    ~notifySlotChange.(\loop, idx, \empty);
};

// Ciclo do botão RecArm:
//   vazio       → grava (~loopRecord)
//   gravando    → para gravação → vai para \stopped (~loopStopRecord)
//   stopped     → nova gravação sobre o anterior (~loopRecord limpa buffer)
//   playing     → volta para \stopped (interrompe playback mas mantém buffer)
//   overdubbing → volta para \stopped
//
// Playback é responsabilidade EXCLUSIVA do botão MUTE (~loopToggleMute abaixo).
// Isto separa "gerenciar gravação" de "controlar reprodução".
~loopToggleRecord = { |idx|
    var slot;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~loopSlots[idx];
    case
    { slot[\state] == \empty }       { ~loopRecord.(idx) }
    { slot[\state] == \recording }   { ~loopStopRecord.(idx) }
    { slot[\state] == \stopped }     { ~loopRecord.(idx) }
    { slot[\state] == \playing }     { ~loopStop.(idx) }
    { slot[\state] == \overdubbing } { ~loopStop.(idx) };
};

// Ciclo do botão MUTE:
//   stopped com áudio → toca (~loopPlay)
//   playing           → pausa (~loopStop)
//   overdubbing       → pausa (~loopStop)
//   qualquer outro    → ignorado
~loopToggleMute = { |idx|
    var slot;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~loopSlots[idx];
    case
    { slot[\state] == \stopped }     {
        if(slot[\frames] > 0) { ~loopPlay.(idx) } {
            ("Loop [" ++ idx ++ "] vazio — grave primeiro com RecArm.").postln;
        };
    }
    { slot[\state] == \playing }     { ~loopStop.(idx) }
    { slot[\state] == \overdubbing } { ~loopStop.(idx) };
    // \empty e \recording: ignora
};


// ---- Controle paramétrico em runtime --------------------------------
~loopSetAmp  = { |idx, amp = 1|  ~loopSlots[idx][\synth] !? { |sy| sy.set(\amp, amp) } };
~loopSetRate = { |idx, rate = 1| ~loopSlots[idx][\synth] !? { |sy| sy.set(\rate, rate) } };
~loopSetPan  = { |idx, pan = 0|  ~loopSlots[idx][\synth] !? { |sy| sy.set(\pan, pan) } };


// ---- Roteamento por slot --------------------------------------------
// Define se o slot vai pra fx, raw, ou both (em tempo real, se tocando).
~loopSetRoute = { |idx, route = \fx|
    var slot, amps;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~loopSlots[idx];
    slot[\route] = route;
    amps = ~routeAmps.(route);
    slot[\synth] !? { |sy| sy.set(\sendFx, amps[0], \sendRaw, amps[1]) };
    ("Loop [" ++ idx ++ "] roteamento: " ++ route).postln;
    ~onSlotRouteChanged !? { |fn| fn.value(\loop, idx, route) };
};

~sampleSetRoute = { |idx, route = \fx|
    var slot, amps;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    slot = ~sampleSlots[idx];
    slot[\route] = route;
    // Se estiver tocando agora, aplica no synth vivo (com lag suave)
    if(slot[\playSynth].notNil) {
        amps = ~routeAmps.(route);
        slot[\playSynth].set(\sendFx, amps[0], \sendRaw, amps[1]);
    };
    ("Sample [" ++ idx ++ "] roteamento: " ++ route).postln;
    ~onSlotRouteChanged !? { |fn| fn.value(\sample, idx, route) };
};

// Cicla \fx → \raw → \both → \fx
~loopCycleRoute = { |idx|
    var current, next;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    current = ~loopSlots[idx][\route];
    next = case
        { current == \fx }   { \raw }
        { current == \raw }  { \both }
        { current == \both } { \fx }
        { \fx };
    ~loopSetRoute.(idx, next);
};

~sampleCycleRoute = { |idx|
    var current, next;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    current = ~sampleSlots[idx][\route];
    next = case
        { current == \fx }   { \raw }
        { current == \raw }  { \both }
        { current == \both } { \fx }
        { \fx };
    ~sampleSetRoute.(idx, next);
};


// =====================================================================
//   CHANNEL ROUTING — escolha de input por slot (stereo/ch1/ch2)
// =====================================================================
// Cada slot pode gravar do ch1 da Focusrite, do ch2, ou de ambos
// (default). A escolha é aplicada na próxima gravação — não tem efeito
// em loops/samples já capturados.

~loopSetCh = { |idx, ch = \stereo|
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    ~loopSlots[idx][\inputCh] = ch;
    ("Loop [" ++ idx ++ "] input ← " ++ ch).postln;
    ~onSlotRoutingChanged !? { |fn| fn.value(\loop, idx, \inputCh, ch) };
};

~sampleSetCh = { |idx, ch = \stereo|
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    ~sampleSlots[idx][\inputCh] = ch;
    ("Sample [" ++ idx ++ "] input ← " ++ ch).postln;
    ~onSlotRoutingChanged !? { |fn| fn.value(\sample, idx, \inputCh, ch) };
};

~loopCycleCh = { |idx|
    var current, next;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    current = ~loopSlots[idx][\inputCh] ? \stereo;
    next = case
        { current == \stereo } { \ch1 }
        { current == \ch1 }    { \ch2 }
        { current == \ch2 }    { \stereo }
        { \stereo };
    ~loopSetCh.(idx, next);
};

~sampleCycleCh = { |idx|
    var current, next;
    if(idx < 0 or: { idx >= 8 }) { ^nil };
    current = ~sampleSlots[idx][\inputCh] ? \stereo;
    next = case
        { current == \stereo } { \ch1 }
        { current == \ch1 }    { \ch2 }
        { current == \ch2 }    { \stereo }
        { \stereo };
    ~sampleSetCh.(idx, next);
};
