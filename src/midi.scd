// =====================================================================
// LIVE ELECTRONICS — midi.scd
// =====================================================================
// MIDI handler para AKAI MIDIMIX. Bidirecional (entrada + LEDs).
// Mapeamento contextual: significado dos controles depende da aba ativa.
//
// Estrutura de bindings:
//   ~midiBindings[\cc][num] = symbol | Association(role -> col)
//   ~midiBindings[\note][num] = symbol | Association(role -> col)
//
// Symbols simples são globais; Associations são contextuais (dispatcher
// resolve baseado na aba ativa).
//
// MIDI Learn:
//   ~midiLearn.(\fxMix_timeStretch)  → próximo evento MIDI mapeia.
//   ~midiLearnCancel.()              → cancela.
//
// Save/load:
//   ~midiSaveMap.("path.scd")    /   ~midiLoadMap.("path.scd")
// =====================================================================


// ---- Flag de debug (definir como true para postar atividade MIDI) -----
~midiDebug = false;


// ---- Números MIDI da AKAI MIDIMIX (canal 1) -------------------------
~midimix = IdentityDictionary[
    \knobsTop -> [16, 20, 24, 28, 46, 50, 54, 58],
    \knobsMid -> [17, 21, 25, 29, 47, 51, 55, 59],
    \knobsBot -> [18, 22, 26, 30, 48, 52, 56, 60],
    \faders   -> [19, 23, 27, 31, 49, 53, 57, 61],
    \master   -> 62,
    \muteNotes   -> [1, 4, 7, 10, 13, 16, 19, 22],
    \recArmNotes -> [3, 6, 9, 12, 15, 18, 21, 24],
    \bankLeft -> 25,
    \bankRight -> 26,
    \solo -> 27
];


// ---- Mapeamento de parâmetros dos efeitos para knobs TOP/MID/BOT ----
// Convenção:
//   TOP   = pan (-1 a +1, knob center = 0)
//   MID   = parâmetro principal #1 do efeito
//   BOT   = parâmetro principal #2 do efeito (ou nil se não houver)
//   FADER = mix (amount do efeito)
//   MUTE  = bypass
// Parâmetros adicionais ficam disponíveis apenas na GUI.
~fxControlMap = IdentityDictionary[
    \timeStretch -> IdentityDictionary[\top -> \pan, \mid -> \stretch,    \bot -> \windowSize],
    \reverse     -> IdentityDictionary[\top -> \pan, \mid -> \segmentDur, \bot -> \density],
    \adsr        -> IdentityDictionary[\top -> \pan, \mid -> \atk,        \bot -> \rel],
    \modulation  -> IdentityDictionary[\top -> \pan, \mid -> \modFreq,   \bot -> \depth],
    \filter      -> IdentityDictionary[\top -> \pan, \mid -> \lpfFreq,    \bot -> \hpfFreq],
    \reverb      -> IdentityDictionary[\top -> \pan, \mid -> \decay,      \bot -> \size],
    \delay       -> IdentityDictionary[\top -> \pan, \mid -> \time,       \bot -> \feedback],
    \harmonizer  -> IdentityDictionary[\top -> \pan, \mid -> \voices,     \bot -> \spread]
];

// Ranges para mapeamento de 0..1 → valor real
~fxParamRanges = IdentityDictionary[
    \pan -> [-1, 1],
    \stretch    -> [0.25, 4],   \windowSize -> [0.02, 1],   \overlaps -> [1, 16],
    \segmentDur -> [0.1, 4],    \density    -> [0.25, 4],
    \atk -> [0.001, 4], \dec -> [0.001, 4], \sus -> [0, 1], \rel -> [0.001, 8],
    \modFreq -> [1, 5000], \depth -> [0, 1], \ratio -> [0.1, 16],
    \mode -> [0, 2],
    \lpfFreq -> [50, 20000], \hpfFreq -> [20, 10000],
    \lowGain -> [-24, 24], \midGain -> [-24, 24], \highGain -> [-24, 24],
    \decay -> [0.1, 30], \size -> [0.5, 3], \damp -> [0, 1],
    \time -> [0.001, 2], \feedback -> [0, 0.95],
    \voices -> [1, 8],   \spread -> [0, 12],
    \mix -> [0, 2]
];

~fxParamExpScale = IdentitySet[\lpfFreq, \hpfFreq, \modFreq, \decay, \time];

~scaleFromNorm = { |paramName, norm|
    var range = ~fxParamRanges[paramName];
    if(range.isNil) { ^norm };
    if(~fxParamExpScale.includes(paramName)) {
        ^range[0] * ((range[1] / range[0]) ** norm)
    };
    ^norm.linlin(0, 1, range[0], range[1])
};


// =====================================================================
//   INICIALIZAÇÃO
// =====================================================================

// Conecta inputs MIDI individualmente. Se um device estiver em uso
// por outro programa, captura o erro e segue adiante.
~tryConnectMidiSources = {
    var connected = 0, failed = List.new;
    if(MIDIClient.sources.notNil) {
        MIDIClient.sources.do { |src|
            try {
                MIDIIn.connect(0, src);
                connected = connected + 1;
            } { |err|
                failed.add(src.name.asString);
            };
        };
    };
    if(connected > 0) {
        ("MIDI: " ++ connected ++ " input(s) conectado(s).").postln;
    };
    if(failed.size > 0) {
        "".postln;
        "MIDI: NÃO consegui conectar:".postln;
        failed.do { |n| ("   ✗ " ++ n).postln };
        "    → outro programa está usando esses dispositivos.".postln;
        "    → feche AKAI MIDIMIX Editor, Focusrite Control, DAW etc.".postln;
        "    → depois execute ~reconnectMidi.value para tentar de novo".postln;
        "".postln;
    };
};

~initMidi = {
    ~midiOut = nil;
    ~midiLearnTarget = nil;
    ~midiOutgoingNotes = IdentitySet.new;  // anti-loopback

    // Flags de comportamento.
    // ~midiFxLedEnabled: enviar noteOn para acender LED de bypass dos efeitos?
    //   Mantém DESLIGADO por padrão — alguns drivers MIDI em Windows travam.
    // ~midiDebug: imprimir cada CC e Note no Post window?
    if(~midiFxLedEnabled.isNil) { ~midiFxLedEnabled = false };
    if(~midiDebug.isNil)        { ~midiDebug = true };  // útil para diagnóstico

    MIDIClient.init(verbose: false);

    // Tenta conectar todos os inputs, tolerando falhas
    ~tryConnectMidiSources.value;

    // Procura MIDIMIX como output (para LEDs)
    block { |break|
        if(MIDIClient.destinations.notNil) {
            MIDIClient.destinations.do { |dest, i|
                var raw = (dest.device.asString ++ " " ++ dest.name.asString).toLower;
                var nameClean = raw.select { |c| c != $  };  // remove espaços
                if(nameClean.contains("midimix")) {
                    try {
                        ~midiOut = MIDIOut.new(i);
                        ~midiOut.latency = 0;
                        ("MIDI: MIDIMIX out conectada (" ++ dest.name ++ ").").postln;
                        break.value;
                    } { |err|
                        ("MIDI: falhou ao abrir output MIDIMIX — " ++ err.errorString).postln;
                    };
                };
            };
        };
    };

    // Bindings default (sempre criados, mesmo se MIDI não conectar)
    ~setupDefaultBindings.value;

    // Handlers — SEMPRE re-criados (libera antigos primeiro para
    // evitar capturas obsoletas de boots anteriores). try-catch garante
    // que uma exceção em um callback não derruba o handler.
    if(~midiCCFunc.notNil)      { ~midiCCFunc.free };
    if(~midiNoteOnFunc.notNil)  { ~midiNoteOnFunc.free };
    if(~midiNoteOffFunc.notNil) { ~midiNoteOffFunc.free };

    ~midiCCFunc = MIDIFunc.cc({ |val, num, chan, src|
        try {
            ~handleMidiCC.(num, val);
        } { |err|
            ("MIDI CC handler error (cc=" ++ num ++ "): " ++ err.errorString).postln;
        };
    });
    ~midiNoteOnFunc = MIDIFunc.noteOn({ |vel, num, chan, src|
        try {
            if(vel > 0) { ~handleMidiNote.(num, true) } { ~handleMidiNote.(num, false) };
        } { |err|
            ("MIDI noteOn handler error (note=" ++ num ++ "): " ++ err.errorString).postln;
        };
    });
    ~midiNoteOffFunc = MIDIFunc.noteOff({ |vel, num, chan, src|
        try {
            ~handleMidiNote.(num, false);
        } { |err|
            ("MIDI noteOff handler error (note=" ++ num ++ "): " ++ err.errorString).postln;
        };
    });

    // Hooks para GUI chamar
    ~syncMidiLedForSlot = { |kind, idx, newState|
        ~handleSlotLedChange.(kind, idx, newState);
    };
    ~syncMidiLedForFx = { |fxName, byp|
        ~handleFxLedChange.(fxName, byp);
    };
    ~syncMidiLedsForTab = { |tabName|
        ~refreshAllLeds.(tabName);
    };

    // Sync inicial dos LEDs (só envia se ~midiOut existir)
    AppClock.sched(0.3, { ~refreshAllLeds.(~state[\activeTab]); nil });
};


// Tenta reconectar MIDI sem precisar fazer cleanup + boot completo.
// Útil quando você fechou o programa concorrente e quer plugar a controladora.
~reconnectMidi = {
    "Tentando reconectar MIDI...".postln;
    try {
        MIDIClient.disposeClient;
    } { };
    MIDIClient.init(verbose: false);
    ~tryConnectMidiSources.value;

    // Re-procura MIDIMIX out
    ~midiOut = nil;
    block { |break|
        if(MIDIClient.destinations.notNil) {
            MIDIClient.destinations.do { |dest, i|
                var raw = (dest.device.asString ++ " " ++ dest.name.asString).toLower;
                var nameClean = raw.select { |c| c != $  };
                if(nameClean.contains("midimix")) {
                    try {
                        ~midiOut = MIDIOut.new(i);
                        ~midiOut.latency = 0;
                        ("MIDI: MIDIMIX out reconectada (" ++ dest.name ++ ").").postln;
                        break.value;
                    } { };
                };
            };
        };
    };
    AppClock.sched(0.3, { ~refreshAllLeds.(~state[\activeTab]); nil });
};


// =====================================================================
//   BINDINGS DEFAULT
// =====================================================================
~setupDefaultBindings = {
    ~midiBindings = IdentityDictionary.new;
    ~midiBindings[\cc] = IdentityDictionary.new;
    ~midiBindings[\note] = IdentityDictionary.new;

    // Knobs e faders → contextual (depende da aba)
    8.do { |col|
        ~midiBindings[\cc][~midimix[\knobsTop][col]] = Association(\col_top, col);
        ~midiBindings[\cc][~midimix[\knobsMid][col]] = Association(\col_mid, col);
        ~midiBindings[\cc][~midimix[\knobsBot][col]] = Association(\col_bot, col);
        ~midiBindings[\cc][~midimix[\faders][col]]   = Association(\col_fader, col);
        ~midiBindings[\note][~midimix[\muteNotes][col]]   = Association(\col_mute, col);
        ~midiBindings[\note][~midimix[\recArmNotes][col]] = Association(\col_recarm, col);
    };

    // Master fader → masterAmp global
    ~midiBindings[\cc][~midimix[\master]] = \global_masterAmp;

    // Navegação
    ~midiBindings[\note][~midimix[\bankLeft]]  = \nav_left;
    ~midiBindings[\note][~midimix[\bankRight]] = \nav_right;
    ~midiBindings[\note][~midimix[\solo]]      = \toggle_mode;
};


// =====================================================================
//   HANDLERS DE ENTRADA MIDI
// =====================================================================
~handleMidiCC = { |cc, val|
    try {
        var binding = ~midiBindings[\cc][cc];
        var normVal = val / 127;

        if(~midiDebug == true) {
            ("MIDI CC " ++ cc ++ " = " ++ val ++ " → binding: " ++ binding).postln;
        };

        if(~midiLearnTarget.notNil) {
            ~midiBindings[\cc][cc] = ~midiLearnTarget;
            ("MIDI Learn: CC " ++ cc ++ " → " ++ ~midiLearnTarget).postln;
            ~gui[\statusText] !? { |t| t.string_(" Mapeado: CC " ++ cc ++ " → " ++ ~midiLearnTarget) };
            ~midiLearnTarget = nil;
        } {
            if(binding.notNil) {
                if(binding.class == Association) {
                    ~dispatchContextualCC.(binding.key, binding.value, normVal);
                } {
                    ~dispatchGlobalCC.(binding, normVal);
                };
            };
        };
    } { |err|
        ("!! ERRO em handleMidiCC (cc=" ++ cc ++ " val=" ++ val ++ "): " ++ err.errorString).postln;
    };
};

~handleMidiNote = { |note, on|
    try {
        var binding, isLoopback;

        if(~midiDebug == true) {
            ("MIDI Note " ++ note ++ " " ++ if(on, "ON", "OFF")).postln;
        };

        isLoopback = ~midiOutgoingNotes.notNil
                     and: { ~midiOutgoingNotes.includes(note) };

        if(isLoopback) {
            if(~midiDebug == true) { "  → IGNORADO (loopback)".postln };
        } {
            binding = ~midiBindings[\note][note];

            if(~midiLearnTarget.notNil and: { on }) {
                ~midiBindings[\note][note] = ~midiLearnTarget;
                ("MIDI Learn: Note " ++ note ++ " → " ++ ~midiLearnTarget).postln;
                ~gui[\statusText] !? { |t| t.string_(" Mapeado: Note " ++ note ++ " → " ++ ~midiLearnTarget) };
                ~midiLearnTarget = nil;
            } {
                if(binding.notNil) {
                    if(~midiDebug == true) { ("  → binding: " ++ binding).postln };
                    if(binding.class == Association) {
                        ~dispatchContextualNote.(binding.key, binding.value, on);
                    } {
                        if(on) { ~dispatchGlobalNote.(binding) };
                    };
                };
            };
        };
    } { |err|
        ("!! ERRO em handleMidiNote (note=" ++ note ++ " on=" ++ on ++ "): " ++ err.errorString).postln;
    };
};


// =====================================================================
//   DISPATCH CONTEXTUAL — significado depende da aba ativa
// =====================================================================
~dispatchContextualCC = { |role, col, normVal|
    var tab = ~state[\activeTab];

    case
    { tab == \effects } { ~dispatchFxCC.(role, col, normVal) }
    { tab == \loops }   { ~dispatchLoopCC.(role, col, normVal) }
    { tab == \samples } { ~dispatchSampleCC.(role, col, normVal) }
    { tab == \master }  { ~dispatchMasterCC.(role, col, normVal) }
    { tab == \presets } { ~dispatchPresetCC.(role, col, normVal) };
};

// Aba Presets: knobs/faders não fazem nada (presets são acionados pelos
// botões físicos RecArm = LOAD, Mute = SAVE)
~dispatchPresetCC = { |role, col, normVal|
    // intencionalmente vazio
};

~dispatchFxCC = { |role, col, normVal|
    var fxList = [\timeStretch, \reverse, \adsr, \modulation, \filter,
                  \reverb, \delay, \harmonizer];
    var fxName, controlMap, paramName;

    if(col < fxList.size) {
        fxName = fxList[col];
        controlMap = ~fxControlMap[fxName];

        if(role == \col_fader) {
            // FADER: sempre controla mix do efeito
            ~fxMix.(fxName, normVal * 2);
        } {
            // TOP/MID/BOT: parâmetros do efeito
            paramName = nil;
            if(role == \col_top)   { paramName = controlMap[\top] };
            if(role == \col_mid)   { paramName = controlMap[\mid] };
            if(role == \col_bot)   { paramName = controlMap[\bot] };

            if(paramName.notNil) {
                if(~midiDebug == true) {
                    ("MIDI fx " ++ fxName ++ " " ++ paramName ++ " ← " ++ normVal.round(0.001)).postln;
                };
                ~setFxParamFromNorm.(fxName, paramName, normVal);
            };
        };
    };
};

~dispatchLoopCC = { |role, col, normVal|
    case
    { role == \col_top }   { ~loopSetAmp.(col, normVal * 2) }
    { role == \col_mid }   { ~loopSetRate.(col, normVal.linlin(0, 1, 0.25, 4)) }
    { role == \col_bot }   { ~loopSetPan.(col, normVal.linlin(0, 1, -1, 1)) }
    { role == \col_fader } { ~loopSetAmp.(col, normVal * 2) };
};

~dispatchSampleCC = { |role, col, normVal|
    // Samples são one-shot, sem ajuste pós-gravação.
    // Faders podem ajustar volume global, talvez. Por ora, vazio.
};

~dispatchMasterCC = { |role, col, normVal|
    if(role == \col_top) {
        case
        { col == 0 } { ~setWetDry.(normVal) }
        { col == 1 } { ~setInputGain.(normVal * 4) }
        { col == 2 } { ~setMasterAmp.(normVal) };
    };
};

~dispatchContextualNote = { |role, col, on|
    var tab = ~state[\activeTab];

    case
    { tab == \effects } { ~dispatchFxNote.(role, col, on) }
    { tab == \samples } { ~dispatchSampleNote.(role, col, on) }
    { tab == \loops }   { ~dispatchLoopNote.(role, col, on) }
    { tab == \presets } { ~dispatchPresetNote.(role, col, on) };
};

// Aba Presets:
//   RecArm coluna i → LOAD preset i
//   Mute   coluna i → SAVE preset i (sobrescreve)
~dispatchPresetNote = { |role, col, on|
    if(on and: { col >= 0 } and: { col < ~presetCount }) {
        case
        { role == \col_recarm } { ~presetLoad.(col) }
        { role == \col_mute }   { ~presetSave.(col) };
    };
};

~dispatchFxNote = { |role, col, on|
    var fxList = [\timeStretch, \reverse, \adsr, \modulation, \filter,
                  \reverb, \delay, \harmonizer];
    var fxName, newByp;
    if(on) {
        if(col < fxList.size) {
            fxName = fxList[col];
            if(role == \col_mute) {
                newByp = 1 - ~fxBypassState[fxName];
                ~fxBypass.(fxName, newByp);
            };
            if((role == \col_recarm) and: { fxName == \adsr }) {
                ~fxAdsrTrig.(0.5);
            };
        };
    };
};

~dispatchSampleNote = { |role, col, on|
    case
    { role == \col_recarm } {
        if(on) { ~samplePress.(col) } { ~sampleRelease.(col) };
    }
    { role == \col_mute and: { on } } {
        // Toggle play/pause do sample gravado. Respeita a rota
        // (fx/raw/both) e passa pelos efeitos quando \fx ou \both.
        ~sampleToggle.(col);
    };
};

~dispatchLoopNote = { |role, col, on|
    if(on) {
        case
        { role == \col_recarm } { ~loopToggleRecord.(col) }
        { role == \col_mute }   { ~loopToggleMute.(col) };
    };
};


// =====================================================================
//   DISPATCH GLOBAL — independe da aba
// =====================================================================
~dispatchGlobalCC = { |binding, normVal|
    case
    { binding == \global_masterAmp } { ~setMasterAmp.(normVal) }
    { binding == \global_wetDry }    { ~setWetDry.(normVal) }
    { binding == \global_inputGain } { ~setInputGain.(normVal * 4) };
};

~dispatchGlobalNote = { |binding|
    case
    { binding == \nav_left }    { ~navigateTab.(-1) }
    { binding == \nav_right }   { ~navigateTab.(1) }
    { binding == \toggle_mode } {
        ~setMode.(if(~state[\mode] == \off) { \live } { \off });
    };
};

~navigateTab = { |dir|
    var tabs = [\master, \samples, \loops, \effects, \presets];
    var current = tabs.indexOf(~state[\activeTab]) ? 0;
    var next = (current + dir).wrap(0, tabs.size - 1);
    defer { ~switchTab.(tabs[next]) };
};


// =====================================================================
//   HELPER — parametro de fx via valor normalizado
// =====================================================================
~setFxParamFromNorm = { |fxName, paramName, normVal|
    var range, exp, realVal;
    try {
        range = ~fxParamRanges[paramName];
        if(range.isNil) {
            ("!! Range não definido para " ++ paramName ++ " — usando normVal cru").postln;
            realVal = normVal;
        } {
            exp = (~fxParamExpScale.notNil) and: { ~fxParamExpScale.includes(paramName) };
            realVal = if(exp) {
                range[0] * ((range[1] / range[0]) ** normVal)
            } {
                normVal.linlin(0, 1, range[0], range[1])
            };
        };

        // mix tem helper específico (clip + notify)
        if(paramName == \mix) {
            ~fxMix.(fxName, realVal);
        } {
            // .set direto, sem passar por ~fxSetParam (que pode estar
            // desatualizado em memória em sessões antigas).
            if(~fx[fxName].notNil) {
                ~fx[fxName].set(paramName, realVal);
                ~fxParamState[fxName] !? { |s| s[paramName] = realVal };
                ~notifyFxChange.(fxName, paramName, realVal);
                ("    .set " ++ fxName ++ "." ++ paramName ++ " = "
                 ++ realVal.round(0.001) ++ " (synth id " ++ ~fx[fxName].nodeID ++ ")").postln;
            } {
                ("!! ~fx[" ++ fxName ++ "] é nil").postln;
            };
        };
    } { |err|
        ("!! ERRO em setFxParamFromNorm (" ++ fxName ++ "." ++ paramName
         ++ "): " ++ err.errorString).postln;
    };
};


// =====================================================================
//   LED FEEDBACK (saída MIDI → MIDIMIX)
// =====================================================================
~setLed = { |note, on = true|
    // SEMPRE via defer para AppClock. Chamar MIDIOut.noteOn a partir do
    // callback PortMidi (MIDI input thread) causa deadlock no mutex
    // interno do PortMidi em Windows — congela toda a entrada MIDI.
    defer {
        if(~midiOut.notNil) {
            if(~midiOutgoingNotes.notNil) {
                ~midiOutgoingNotes.add(note);
                AppClock.sched(0.08, {
                    ~midiOutgoingNotes !? { |s| s.remove(note) };
                    nil
                });
            };
            try {
                ~midiOut.noteOn(0, note, if(on, 127, 0));
                if(~midiDebug == true) {
                    ("MIDI LED out: note " ++ note ++ " " ++ if(on, "ON", "OFF")).postln;
                };
            } { |err|
                ("MIDI LED out FAILED (note=" ++ note ++ "): " ++ err.errorString).postln;
            };
        };
    };
};

~handleSlotLedChange = { |kind, idx, newState|
    var tab = ~state[\activeTab];
    var relevant = ((tab == \samples) and: { kind == \sample })
                   or: { (tab == \loops) and: { kind == \loop } };
    if(relevant) {
        if(kind == \sample) {
            ~setLed.(~midimix[\recArmNotes][idx], newState == \recording);
            ~setLed.(~midimix[\muteNotes][idx],   newState == \playing);
        } {
            ~setLed.(~midimix[\recArmNotes][idx], newState == \recording);
            ~setLed.(~midimix[\muteNotes][idx],
                (newState == \playing) or: { newState == \overdubbing });
        };
    };
};

~handleFxLedChange = { |fxName, byp|
    if(~midiFxLedEnabled == true) {
        var fxList = [\timeStretch, \reverse, \adsr, \modulation, \filter,
                      \reverb, \delay, \harmonizer];
        var col = fxList.indexOf(fxName);
        if(~state[\activeTab] == \effects and: { col.notNil }) {
            ~setLed.(~midimix[\muteNotes][col], byp == 0);
        };
    };
};

~refreshAllLeds = { |tabName|
    // Apaga todos os LEDs primeiro
    (~midimix[\muteNotes] ++ ~midimix[\recArmNotes]).do { |n| ~setLed.(n, false) };

    case
    { tabName == \effects } {
        if(~midiFxLedEnabled == true) {
            var fxList = [\timeStretch, \reverse, \adsr, \modulation, \filter,
                          \reverb, \delay, \harmonizer];
            fxList.do { |fx, i|
                ~setLed.(~midimix[\muteNotes][i], ~fxBypassState[fx] == 0);
            };
        };
    }
    { tabName == \samples } {
        ~sampleSlots.do { |slot, i|
            ~setLed.(~midimix[\recArmNotes][i], slot[\state] == \recording);
            ~setLed.(~midimix[\muteNotes][i],   slot[\state] == \playing);
        };
    }
    { tabName == \loops } {
        ~loopSlots.do { |slot, i|
            ~setLed.(~midimix[\recArmNotes][i], slot[\state] == \recording);
            ~setLed.(~midimix[\muteNotes][i],
                (slot[\state] == \playing) or: { slot[\state] == \overdubbing });
        };
    }
    { tabName == \presets } {
        // Mute[i]   aceso = preset i está salvo (botão SAVE corresponde)
        // RecArm[i] aceso = preset i é o ativo carregado (LOAD)
        if(~presetCount.notNil) {
            ~presetCount.do { |i|
                ~setLed.(~midimix[\muteNotes][i], ~presets[i][\saved]);
                ~setLed.(~midimix[\recArmNotes][i], ~activePreset == i);
            };
        };
    };
};


// =====================================================================
//   MIDI LEARN
// =====================================================================
~midiLearn = { |controlSymbol|
    ~midiLearnTarget = controlSymbol;
    ("MIDI Learn aguardando para: " ++ controlSymbol).postln;
    ~gui[\statusText] !? { |t|
        t.string_(" MIDI Learn ativo — mova um controle físico para mapear ‹"
                  ++ controlSymbol ++ "›");
    };
};

~midiLearnCancel = {
    ~midiLearnTarget = nil;
    ~gui[\statusText] !? { |t| t.string_(" MIDI Learn cancelado.") };
    "MIDI Learn cancelado.".postln;
};


// =====================================================================
//   SAVE / LOAD DE MAPEAMENTOS
// =====================================================================
~midiSaveMap = { |path|
    var file = File(path, "w");
    file.write(~midiBindings.asCompileString);
    file.close;
    ("Mapeamento MIDI salvo: " ++ path).postln;
};

~midiLoadMap = { |path|
    var data;
    if(File.exists(path).not) {
        ("Arquivo não encontrado: " ++ path).postln; ^nil
    };
    data = thisProcess.interpreter.executeFile(path);
    if(data.notNil) {
        ~midiBindings = data;
        ("Mapeamento MIDI carregado: " ++ path).postln;
    };
};


// =====================================================================
//   INSPEÇÃO
// =====================================================================
~midiInspect = {
    "".postln;
    "=== MIDI BINDINGS ===".postln;
    "CC:".postln;
    ~midiBindings[\cc].keysValuesDo { |k, v|
        ("  " ++ k.asString.padLeft(3) ++ " → " ++ v).postln;
    };
    "Note:".postln;
    ~midiBindings[\note].keysValuesDo { |k, v|
        ("  " ++ k.asString.padLeft(3) ++ " → " ++ v).postln;
    };
    "".postln;
};

// Status detalhado do subsistema MIDI: mostra estado de outgoing,
// MIDIFuncs registrados, conexões, etc. Útil para diagnóstico.
~midiStatus = {
    "".postln;
    "=== MIDI STATUS ===".postln;
    ("  midiOut: " ++ ~midiOut).postln;
    ("  sources conectados: " ++ MIDIClient.sources.size).postln;
    MIDIClient.sources.do { |s| ("    " ++ s.name).postln };
    ("  destinations: " ++ MIDIClient.destinations.size).postln;
    MIDIClient.destinations.do { |d| ("    " ++ d.name).postln };
    ("  midiCCFunc:      " ++ ~midiCCFunc).postln;
    ("  midiNoteOnFunc:  " ++ ~midiNoteOnFunc).postln;
    ("  midiNoteOffFunc: " ++ ~midiNoteOffFunc).postln;
    ("  outgoingNotes:   " ++ ~midiOutgoingNotes.asArray).postln;
    ("  debug:           " ++ ~midiDebug).postln;
    ("  aba ativa:       " ++ ~state[\activeTab]).postln;
    "".postln;
    "  fxBypassState:".postln;
    ~fxBypassState.keysValuesDo { |k, v|
        ("    " ++ k.asString.padLeft(13) ++ " = " ++ v).postln;
    };
    "".postln;
};

// Auto-diagnóstico do pipeline MIDI. Roda quando o usuário suspeita
// que os knobs físicos não estão chegando.
// Uso: ~midiSelfTest.value;
~midiSelfTest = {
    var allOk = true;
    "".postln;
    "═══ MIDI SELF-TEST ═══════════════════════════════════".postln;

    // (1) Debug está ativo?
    if(~midiDebug != true) {
        "  ✗ ~midiDebug está OFF — ative com: ~midiDebug = true".postln;
        ~midiDebug = true;
        "    (acabei de ativar)".postln;
        allOk = false;
    } { "  ✓ ~midiDebug = true".postln };

    // (2) MIDIFunc registrado?
    if(~midiCCFunc.isNil) {
        "  ✗ ~midiCCFunc NÃO está registrado — MIDI input não chega.".postln;
        "    Rode ~midiReset.value para recriar.".postln;
        allOk = false;
    } { "  ✓ ~midiCCFunc registrado.".postln };

    // (3) MIDI sources conectadas?
    if(MIDIClient.sources.notNil and: { MIDIClient.sources.size > 0 }) {
        "  ✓ MIDI sources:".postln;
        MIDIClient.sources.do { |src| ("      " ++ src.name).postln };
    } {
        "  ✗ Nenhuma source MIDI conectada.".postln;
        "    Tente ~reconnectMidi.value".postln;
        allOk = false;
    };

    // (4) Bindings dos knobs?
    if(~midiBindings[\cc][16].notNil) {
        ("  ✓ CC 16 → " ++ ~midiBindings[\cc][16]).postln;
    } {
        "  ✗ CC 16 sem binding — bindings não foram configurados.".postln;
        allOk = false;
    };

    // (5) fxControlMap atualizado?
    if(~fxControlMap[\timeStretch][\top] == \pan) {
        "  ✓ fxControlMap[timeStretch][top] = pan".postln;
    } {
        ("  ✗ fxControlMap[timeStretch][top] = " ++ ~fxControlMap[\timeStretch][\top]
          ++ " (esperado: pan) — arquivo midi.scd antigo em memória").postln;
        allOk = false;
    };

    // (6) Range do pan?
    if(~fxParamRanges[\pan] == [-1, 1]) {
        "  ✓ fxParamRanges[pan] = [-1, 1]".postln;
    } {
        ("  ✗ fxParamRanges[pan] = " ++ ~fxParamRanges[\pan]
          ++ " (esperado [-1, 1])").postln;
        allOk = false;
    };

    // (7) Synth do efeito existe?
    if(~fx[\timeStretch].notNil) {
        ("  ✓ ~fx[timeStretch] = " ++ ~fx[\timeStretch]).postln;
    } {
        "  ✗ ~fx[timeStretch] é nil — efeito não foi inicializado.".postln;
        allOk = false;
    };

    "".postln;
    if(allOk) {
        " ✓✓ Tudo OK. Knobs devem funcionar. Gire um e veja o Post.".postln;
    } {
        " ✗✗ Há problemas. Se o fxControlMap está errado, recarregue".postln;
        "    o arquivo main.scd inteiro (não só ~boot).".postln;
    };
    "═══════════════════════════════════════════════════════".postln;
    "".postln;
};



// Reset preventivo: limpa state que pode estar travado e
// recria os handlers MIDI. Não precisa rebootar o servidor.
~midiReset = {
    "Resetando subsistema MIDI...".postln;

    // Limpa set de outgoing (caso esteja preso)
    ~midiOutgoingNotes !? { |s| s.clear };
    ~midiOutgoingNotes = IdentitySet.new;

    // Re-cria handlers
    if(~midiCCFunc.notNil)      { ~midiCCFunc.free;      ~midiCCFunc = nil };
    if(~midiNoteOnFunc.notNil)  { ~midiNoteOnFunc.free;  ~midiNoteOnFunc = nil };
    if(~midiNoteOffFunc.notNil) { ~midiNoteOffFunc.free; ~midiNoteOffFunc = nil };

    ~midiCCFunc = MIDIFunc.cc({ |val, num, chan, src|
        try { ~handleMidiCC.(num, val) } { |err|
            ("MIDI CC error: " ++ err.errorString).postln;
        };
    });
    ~midiNoteOnFunc = MIDIFunc.noteOn({ |vel, num, chan, src|
        try {
            if(vel > 0) { ~handleMidiNote.(num, true) } { ~handleMidiNote.(num, false) };
        } { |err|
            ("MIDI noteOn error: " ++ err.errorString).postln;
        };
    });
    ~midiNoteOffFunc = MIDIFunc.noteOff({ |vel, num, chan, src|
        try { ~handleMidiNote.(num, false) } { |err|
            ("MIDI noteOff error: " ++ err.errorString).postln;
        };
    });

    AppClock.sched(0.2, { ~refreshAllLeds.(~state[\activeTab]); nil });
    "MIDI reset OK.".postln;
};


"MIDI module carregado.".postln;
