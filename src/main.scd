// =====================================================================
// LIVE ELECTRONICS — main.scd
// Prof. Ivan Simurra · NICS/UNICAMP
// =====================================================================
//
// Arquivo principal — execute APENAS este. Os outros 5 módulos são
// carregados automaticamente:
//
//   synthdefs.scd  — todos os SynthDefs
//   slots.scd      — samples (press/release) e loops
//   effects.scd    — 5 efeitos da Fase 3
//   gui.scd        — interface gráfica com 4 abas (Fase 4)
//   midi.scd       — MIDI handler + learn + LED feedback (Fase 4)
//
// Uso:
//   ~boot.value;      // inicializa servidor, módulos, GUI e MIDI
//   ~cleanup.value;   // libera tudo
//
// =====================================================================

(

// ---- Carregamento dos módulos --------------------------------------
~projectRoot = thisProcess.nowExecutingPath.dirname;
"".postln;
"================================================".postln;
"  LIVE ELECTRONICS — carregando módulos".postln;
("  raiz: " ++ ~projectRoot).postln;
"================================================".postln;

#[
    "synthdefs.scd",
    "slots.scd",
    "effects.scd",
    "presets.scd",
    "score.scd",
    "gui.scd",
    "midi.scd"
].do { |fileName|
    var path = ~projectRoot +/+ fileName;
    if(File.exists(path)) {
        thisProcess.interpreter.executeFile(path);
        ("  ✓ " ++ fileName).postln;
    } {
        ("  ✗ FALTANDO: " ++ fileName ++ " em " ++ path).postln;
    };
};
"------------------------------------------------".postln;
"".postln;


// ---- Configuração do servidor --------------------------------------
s = Server.local;
s.options.numInputBusChannels  = 2;
s.options.numOutputBusChannels = 2;
s.options.memSize    = 2 ** 18;
s.options.sampleRate = 48000;
s.options.blockSize  = 64;


// ---- BOOT — orquestração completa ----------------------------------
~boot = {
    s.waitForBoot({

        // 1. Buses
        ~buses = IdentityDictionary.new;
        ~buses[\source] = Bus.audio(s, 2);
        ~buses[\mic]    = Bus.audio(s, 2);
        ~buses[\fx]     = Bus.audio(s, 2);
        ~buses[\raw]    = Bus.audio(s, 2);  // sinal direto dos slots (sem efeitos)
        // Saídas individuais dos 8 efeitos (para encadeamento modular)
        ~buses[\fxOut]  = IdentityDictionary.new;
        [\timeStretch, \reverse, \adsr, \modulation, \filter,
         \reverb, \delay, \harmonizer].do { |fx|
            ~buses[\fxOut][fx] = Bus.audio(s, 2);
        };
        "[1/10] Buses alocados.".postln;

        // 2. Buffers (samples 60s, loops 60s, efeitos internos 4s)
        ~buffers = IdentityDictionary.new;
        ~buffers[\samples] = Array.fill(8, { Buffer.alloc(s, s.sampleRate * 60, 2) });
        ~buffers[\loops]   = Array.fill(8, { Buffer.alloc(s, s.sampleRate * 60, 2) });
        ~buffers[\fxStretch] = Buffer.alloc(s, s.sampleRate * 4, 1);
        ~buffers[\fxReverse] = Buffer.alloc(s, s.sampleRate * 4, 2);
        ~buffers[\fxMod]     = Buffer.alloc(s, s.sampleRate * 4, 1);
        s.sync;
        ~buffers[\fxMod].loadCollection(
            Array.fill(s.sampleRate * 4, { 1.0.rand2 * 0.3 })
        );
        s.sync;
        "[2/10] Buffers alocados (samples e loops: 60s cada).".postln;

        // 3. SynthDefs
        ~loadSynthDefs.value;
        s.sync;
        "[3/10] SynthDefs carregados.".postln;

        // 4. Grupos
        ~groups = IdentityDictionary.new;
        ~groups[\input]    = Group.new(s, \addToTail);
        ~groups[\capture]  = Group.after(~groups[\input]);
        ~groups[\playback] = Group.after(~groups[\capture]);
        ~groups[\fx]       = Group.after(~groups[\playback]);
        ~groups[\master]   = Group.after(~groups[\fx]);
        s.sync;
        "[4/10] Grupos criados.".postln;

        // ---- 5. Estado global ------------------------------------------
        ~state = IdentityDictionary.new;
        ~state[\mode]      = \off;
        ~state[\inputGain] = 1.0;
        ~state[\wetDry]    = 0.5;
        ~state[\masterAmp] = 0.8;
        ~state[\monitor]   = 0;
        ~state[\activeTab] = \effects;
        ~state[\focusedFx] = \timeStretch;
        "[5/10] Estado global inicializado.".postln;

        // 6. Slots + OSCdefs
        ~initSlots.value;
        ~installOSCdefs.value;
        "[6/10] Slots e OSCdefs prontos.".postln;

        // 7. Synths persistentes (input + master)
        ~synths = IdentityDictionary.new;
        ~synths[\input] = Synth(\inputStage, [
            \inBus,   0,
            \rawBus,  ~buses[\raw].index,    // direct monitor vai pro raw
            \micBus,  ~buses[\mic].index,
            \gate,    0,
            \monitor, ~state[\monitor],
            \gain,    ~state[\inputGain]
        ], ~groups[\input]);
        ~synths[\master] = Synth(\masterStage, [
            \fxBus,     ~buses[\fx].index,
            \rawBus,    ~buses[\raw].index,
            \wetDry,    ~state[\wetDry],
            \amp,       ~state[\masterAmp]
        ], ~groups[\master]);
        s.sync;
        "[7/10] Input e master ativos.".postln;

        // 8. Efeitos
        ~initFx.value;
        s.sync;
        "[8/10] Efeitos instanciados.".postln;

        // 8b. Presets (em memória)
        ~initPresets.value;

        // 9. GUI (em AppClock, fora do thread do servidor)
        AppClock.sched(0.1, {
            ~buildGui.value;
            "[9/10] GUI criada.".postln;
            nil
        });

        // 10. MIDI
        AppClock.sched(0.5, {
            ~initMidi.value;
            "[10/10] MIDI inicializado.".postln;
            "".postln;
            "=== BOOT COMPLETO ===".postln;
            "GUI aberta. Atalhos: Cmd/Ctrl+1..4 (abas master/samples/loops/effects)".postln;
            "                     Cmd/Ctrl+0       (aba presets)".postln;
            "                     q w e r t y u i  (samples press/release)".postln;
            "                     1..8             (loops record toggle)".postln;
            "                     Cmd/Ctrl+5..9    (focar efeitos)".postln;
            "MIDI: AKAI MIDIMIX detectada automaticamente se conectada.".postln;
            "".postln;
            "MIDI Debug está ATIVO — cada CC/Note aparece no Post window.".postln;
            "  Para desligar: ~midiDebug = false".postln;
            "LED feedback do bypass está DESLIGADO (causa trava em alguns drivers Win).".postln;
            "  Para ativar:  ~midiFxLedEnabled = true".postln;
            nil
        });
    });
};


// ---- Controles globais ---------------------------------------------
~setMode = { |newMode|
    var openMic = (newMode == \live) or: { newMode == \both };
    ~state[\mode] = newMode;
    ~synths[\input].set(\gate, openMic.binaryValue);
    ~updateModeGui !? { |f| f.value(newMode) };
    ("Modo: " ++ newMode).postln;
};

~setWetDry = { |val|
    val = val.clip(0, 1);
    ~state[\wetDry] = val;
    ~synths[\master].set(\wetDry, val);
    ~updateGlobalKnob !? { |f| f.value(\wetDry, val) };
};

~setMasterAmp = { |val|
    val = val.clip(0, 1);
    ~state[\masterAmp] = val;
    ~synths[\master].set(\amp, val);
    ~updateGlobalKnob !? { |f| f.value(\masterAmp, val) };
};

~setInputGain = { |val|
    val = val.clip(0, 4);
    ~state[\inputGain] = val;
    ~synths[\input].set(\gain, val);
    ~updateGlobalKnob !? { |f| f.value(\inputGain, val) };
};

// Direct monitor: controla se o mic é roteado para sourceBus (saída direta).
// O mic SEMPRE vai para micBus (alimenta os efeitos); monitor=1 acrescenta
// também o caminho direto sem efeitos, útil para monitoramento ao vivo.
~setMonitor = { |on|
    var val = on.asInteger;
    ~state[\monitor] = val;
    ~synths[\input].set(\monitor, val);
    ~updateMonitorGui !? { |f| f.value(val) };
    ("Direct monitor: " ++ (if(val == 1, "ON", "OFF"))).postln;
};


// ---- STATUS --------------------------------------------------------
~status = {
    "".postln;
    "=== STATUS ===".postln;
    ("Modo: " ++ ~state[\mode] ++ "  |  wet/dry: " ++ ~state[\wetDry].round(0.01)
     ++ "  |  master: " ++ ~state[\masterAmp].round(0.01)).postln;
    ("Aba ativa: " ++ ~state[\activeTab] ++ "  |  efeito focado: " ++ ~state[\focusedFx]).postln;
    "".postln;
    "Efeitos:".postln;
    ~fx.keysValuesDo { |k, syn|
        var byp = ~fxBypassState[k] ? "?";
        ("  " ++ k.asString.padRight(14) ++ "  bypass=" ++ byp).postln;
    };
    "".postln;
    "Samples:".postln;
    ~sampleSlots.do { |slot, i|
        ("  [" ++ i ++ "] " ++ slot[\state]
         ++ "  (" ++ (slot[\frames] / s.sampleRate).round(0.01) ++ "s)").postln;
    };
    "Loops:".postln;
    ~loopSlots.do { |slot, i|
        ("  [" ++ i ++ "] " ++ slot[\state]
         ++ "  (dur " ++ slot[\dur] ++ "s, gravado " ++ (slot[\frames] / s.sampleRate).round(0.01) ++ "s)").postln;
    };
    "".postln;
};


// ---- CLEANUP -------------------------------------------------------
~cleanup = {
    // GUI
    if(~window.notNil) { ~window.close; ~window = nil };

    // MIDI
    if(~midiCCFunc.notNil) { ~midiCCFunc.free; ~midiCCFunc = nil };
    if(~midiNoteOnFunc.notNil) { ~midiNoteOnFunc.free; ~midiNoteOnFunc = nil };
    if(~midiNoteOffFunc.notNil) { ~midiNoteOffFunc.free; ~midiNoteOffFunc = nil };
    ~midiOut = nil;

    // Áudio
    if(~sampleSlots.notNil) {
        ~sampleSlots.do { |slot| slot[\recSynth] !? { |sy| sy.free } };
        ~sampleSlots = nil;
    };
    if(~loopSlots.notNil) {
        ~loopSlots.do { |slot| slot[\synth] !? { |sy| sy.free } };
        ~loopSlots = nil;
    };
    OSCdef(\sampleRecorded).free;
    OSCdef(\loopRecorded).free;

    if(~fx.notNil)     { ~fx.do(_.free);      ~fx     = nil };
    if(~synths.notNil) { ~synths.do(_.free);  ~synths = nil };
    if(~groups.notNil) { ~groups.do(_.free);  ~groups = nil };
    if(~buses.notNil)  {
        // ~buses contém Bus (~buses.do funciona) E também o sub-dict fxOut
        // que precisa ser tratado separadamente
        ~buses[\fxOut] !? { |d| d.do(_.free) };
        ~buses[\fxOut] = nil;
        [\source, \mic, \fx, \raw].do { |k| ~buses[k] !? (_.free) };
        ~buses  = nil
    };
    if(~buffers.notNil) {
        ~buffers[\samples].do(_.free);
        ~buffers[\loops].do(_.free);
        ~buffers[\fxStretch].free;
        ~buffers[\fxReverse].free;
        ~buffers[\fxMod].free;
        ~buffers = nil;
    };
    "Sistema desalocado.".postln;
};

"".postln;
"Módulos carregados. Execute ~boot.value para iniciar.".postln;
"".postln;

)
