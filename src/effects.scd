// =====================================================================
// LIVE ELECTRONICS — effects.scd
// =====================================================================
// Inicialização e controle dos 5 efeitos globais.
// Mantém ~fxBypassState (estado espelho) para que GUI e LEDs MIDI fiquem
// sincronizados sem chamadas .get assíncronas.
// =====================================================================


// Estado espelho do bypass (atualizado a cada ~fxBypass)
~fxBypassState = IdentityDictionary[
    \timeStretch -> 1, \reverse -> 1, \adsr -> 1, \modulation -> 1, \filter -> 0,
    \reverb -> 1, \delay -> 1, \harmonizer -> 1
];

// Estado espelho dos parâmetros (para a GUI poder ler sem .get)
~fxParamState = IdentityDictionary[
    \timeStretch -> IdentityDictionary[\mix -> 1, \pan -> 0,
                                       \stretch -> 1, \windowSize -> 0.15, \overlaps -> 4],
    \reverse     -> IdentityDictionary[\mix -> 1, \pan -> 0,
                                       \segmentDur -> 1, \density -> 1],
    \adsr        -> IdentityDictionary[\mix -> 1, \pan -> 0,
                                       \atk -> 0.01, \dec -> 0.1, \sus -> 0.7, \rel -> 0.5],
    \modulation  -> IdentityDictionary[\mix -> 1, \pan -> 0,
                                       \mode -> 0, \modFreq -> 200,
                                       \depth -> 0.5, \ratio -> 1.0],
    \filter      -> IdentityDictionary[\mix -> 1, \pan -> 0,
                                       \lpfFreq -> 20000, \hpfFreq -> 20,
                                       \lpfRq -> 1, \hpfRq -> 1,
                                       \lowGain -> 0, \midGain -> 0, \highGain -> 0,
                                       \midFreq -> 1000],
    \reverb      -> IdentityDictionary[\mix -> 1, \pan -> 0,
                                       \decay -> 2, \size -> 1, \damp -> 0.5],
    \delay       -> IdentityDictionary[\mix -> 1, \pan -> 0,
                                       \time -> 0.5, \feedback -> 0.5],
    \harmonizer  -> IdentityDictionary[\mix -> 1, \pan -> 0,
                                       \voices -> 4, \spread -> 2]
];


// Roteamento por efeito: source (de onde lê) e sendToMaster (se manda
// pro fxBus geral). Estado espelho mantido em sclang.
~fxRouting = IdentityDictionary[
    \timeStretch -> IdentityDictionary[\source -> \dry, \sendToMaster -> 1, \chMode -> 0],
    \reverse     -> IdentityDictionary[\source -> \dry, \sendToMaster -> 1, \chMode -> 0],
    \adsr        -> IdentityDictionary[\source -> \dry, \sendToMaster -> 1, \chMode -> 0],
    \modulation  -> IdentityDictionary[\source -> \dry, \sendToMaster -> 1, \chMode -> 0],
    \filter      -> IdentityDictionary[\source -> \dry, \sendToMaster -> 1, \chMode -> 0],
    \reverb      -> IdentityDictionary[\source -> \dry, \sendToMaster -> 1, \chMode -> 0],
    \delay       -> IdentityDictionary[\source -> \dry, \sendToMaster -> 1, \chMode -> 0],
    \harmonizer  -> IdentityDictionary[\source -> \dry, \sendToMaster -> 1, \chMode -> 0]
];

// Helper: resolve um símbolo de source para o índice do bus
~resolveSrcBus = { |srcName|
    if(srcName == \dry) {
        ~buses[\source].index
    } {
        var b = ~buses[\fxOut][srcName];
        if(b.notNil) { b.index } { ~buses[\source].index }
    };
};

// Helper: converte símbolo de chMode para inteiro
~chModeToInt = { |sym|
    case
    { sym == \stereo } { 0 }
    { sym == \ch1 }    { 1 }
    { sym == \ch2 }    { 2 }
    { 0 };
};

~chIntToSym = { |i|
    case
    { i == 0 } { \stereo }
    { i == 1 } { \ch1 }
    { i == 2 } { \ch2 }
    { \stereo };
};


~initFx = {
    var src = ~buses[\source].index;
    var mic = ~buses[\mic].index;
    var master = ~buses[\fx].index;
    ~fx = IdentityDictionary.new;

    ~fx[\timeStretch] = Synth(\fxTimeStretch, [
        \inBus,    src, \micBus, mic,
        \outBus,   ~buses[\fxOut][\timeStretch].index,
        \masterBus, master,
        \buf, ~buffers[\fxStretch].bufnum,
        \mix, 1.0, \bypass, 1, \stretch, 1
    ], ~groups[\fx]);

    ~fx[\reverse] = Synth(\fxReverse, [
        \inBus,    src, \micBus, mic,
        \outBus,   ~buses[\fxOut][\reverse].index,
        \masterBus, master,
        \buf, ~buffers[\fxReverse].bufnum,
        \mix, 1.0, \bypass, 1, \segmentDur, 1, \density, 1
    ], ~groups[\fx]);

    ~fx[\adsr] = Synth(\fxADSR, [
        \inBus,    src, \micBus, mic,
        \outBus,   ~buses[\fxOut][\adsr].index,
        \masterBus, master,
        \mix, 1.0, \bypass, 1, \gate, 0
    ], ~groups[\fx]);

    ~fx[\modulation] = Synth(\fxModulation, [
        \inBus,    src, \micBus, mic,
        \outBus,   ~buses[\fxOut][\modulation].index,
        \masterBus, master,
        \mix, 1.0, \bypass, 1,
        \mode, 0, \modFreq, 200, \depth, 0.5, \ratio, 1.0
    ], ~groups[\fx]);

    ~fx[\filter] = Synth(\fxFilter, [
        \inBus,    src, \micBus, mic,
        \outBus,   ~buses[\fxOut][\filter].index,
        \masterBus, master,
        \mix, 1.0, \bypass, 0     // único efeito ativo no boot
    ], ~groups[\fx]);

    ~fx[\reverb] = Synth(\fxReverb, [
        \inBus,    src, \micBus, mic,
        \outBus,   ~buses[\fxOut][\reverb].index,
        \masterBus, master,
        \mix, 1.0, \bypass, 1, \decay, 2, \size, 1, \damp, 0.5
    ], ~groups[\fx]);

    ~fx[\delay] = Synth(\fxDelay, [
        \inBus,    src, \micBus, mic,
        \outBus,   ~buses[\fxOut][\delay].index,
        \masterBus, master,
        \mix, 1.0, \bypass, 1, \time, 0.5, \feedback, 0.5
    ], ~groups[\fx]);

    ~fx[\harmonizer] = Synth(\fxHarmonizer, [
        \inBus,    src, \micBus, mic,
        \outBus,   ~buses[\fxOut][\harmonizer].index,
        \masterBus, master,
        \mix, 1.0, \bypass, 1, \voices, 4, \spread, 2
    ], ~groups[\fx]);
};


// Helper interno
~notifyFxChange = { |fxName, paramName, val|
    ~onFxChanged !? { |fn| fn.value(fxName, paramName, val) };
};


// ---- Controle genérico (bypass + mix) -------------------------------
~fxBypass = { |fxName, byp = 1|
    if(~fx[fxName].notNil) {
        ~fx[fxName].set(\bypass, byp.asInteger);
        ~fxBypassState[fxName] = byp.asInteger;
        ~notifyFxChange.(fxName, \bypass, byp.asInteger);
        (fxName ++ " bypass: " ++ byp).postln;
    };
};

~fxBypassAll = { |byp = 1|
    ~fx.keys.do { |k| ~fxBypass.(k, byp) };
};

~fxMix = { |fxName, mix = 1|
    mix = mix.clip(0, 2);
    if(~fx[fxName].notNil) {
        ~fx[fxName].set(\mix, mix);
        ~fxParamState[fxName][\mix] = mix;
        ~notifyFxChange.(fxName, \mix, mix);
    };
};


// ---- Helper interno para set de parâmetro com tracking --------------
~fxSetParam = { |fxName, paramName, val|
    if(~fx[fxName].notNil) {
        ~fx[fxName].set(paramName, val);
        ~fxParamState[fxName][paramName] = val;
        ~notifyFxChange.(fxName, paramName, val);
        if(~midiDebug == true) {
            ("    .set " ++ fxName ++ "." ++ paramName ++ " = "
             ++ val.round(0.001) ++ " (synth id " ++ ~fx[fxName].nodeID ++ ")").postln;
        };
    } {
        ("!! ~fx[" ++ fxName ++ "] é nil — efeito não inicializado.").postln;
    };
};


// ---- Time-stretch ---------------------------------------------------
~fxTimeStretchSet = { |stretch, windowSize, overlaps|
    if(stretch.notNil)    { ~fxSetParam.(\timeStretch, \stretch,    stretch.max(0.1)) };
    if(windowSize.notNil) { ~fxSetParam.(\timeStretch, \windowSize, windowSize.clip(0.02, 1)) };
    if(overlaps.notNil)   { ~fxSetParam.(\timeStretch, \overlaps,   overlaps.clip(1, 16)) };
};

// ---- Reverse --------------------------------------------------------
~fxReverseSet = { |segmentDur|
    if(segmentDur.notNil) { ~fxSetParam.(\reverse, \segmentDur, segmentDur.clip(0.1, 4)) };
};

// ---- ADSR -----------------------------------------------------------
~fxAdsrSet = { |atk, dec, sus, rel|
    if(atk.notNil) { ~fxSetParam.(\adsr, \atk, atk.max(0.001)) };
    if(dec.notNil) { ~fxSetParam.(\adsr, \dec, dec.max(0.001)) };
    if(sus.notNil) { ~fxSetParam.(\adsr, \sus, sus.clip(0, 1)) };
    if(rel.notNil) { ~fxSetParam.(\adsr, \rel, rel.max(0.001)) };
};

~fxAdsrGate = { |gate|
    ~fx[\adsr].set(\gate, gate.asInteger);
    ~notifyFxChange.(\adsr, \gate, gate.asInteger);
};

~fxAdsrTrig = { |holdDur = 0.5|
    ~fx[\adsr].set(\gate, 1);
    ~notifyFxChange.(\adsr, \gate, 1);
    AppClock.sched(holdDur, {
        ~fx[\adsr].set(\gate, 0);
        ~notifyFxChange.(\adsr, \gate, 0);
        nil
    });
};

// ---- Modulation (RM / AM / FM) ------------------------------------
// Os 3 modos compartilham a mesma SynthDef; o knob MODE alterna entre
// os ramos internos. Cada modo usa um subconjunto dos params:
//   RM = modFreq, ratio                (depth ignorada)
//   AM = modFreq, depth, ratio
//   FM = modFreq, depth, ratio
~fxModNames = #[\rm, \am, \fm];

~fxModulationSetMode = { |modeName|
    var idx = ~fxModNames.indexOf(modeName.asSymbol);
    if(idx.isNil) {
        ("!! Modo desconhecido: " ++ modeName ++ ". Use \\rm, \\am ou \\fm.").postln;
    } {
        ~fxSetParam.(\modulation, \mode, idx);
        ("modulation mode ← " ++ modeName).postln;
    };
};

~fxModulationSet = { |modFreq, depth, ratio|
    if(modFreq.notNil) { ~fxSetParam.(\modulation, \modFreq, modFreq) };
    if(depth.notNil)   { ~fxSetParam.(\modulation, \depth,   depth.clip(0, 1)) };
    if(ratio.notNil)   { ~fxSetParam.(\modulation, \ratio,   ratio.clip(0.1, 16)) };
};

// ---- Filter + EQ ----------------------------------------------------
~fxFilterSet = { |lpfFreq, hpfFreq, lpfRq, hpfRq, lowGain, midGain, highGain, midFreq|
    if(lpfFreq.notNil)  { ~fxSetParam.(\filter, \lpfFreq,  lpfFreq) };
    if(hpfFreq.notNil)  { ~fxSetParam.(\filter, \hpfFreq,  hpfFreq) };
    if(lpfRq.notNil)    { ~fxSetParam.(\filter, \lpfRq,    lpfRq) };
    if(hpfRq.notNil)    { ~fxSetParam.(\filter, \hpfRq,    hpfRq) };
    if(lowGain.notNil)  { ~fxSetParam.(\filter, \lowGain,  lowGain) };
    if(midGain.notNil)  { ~fxSetParam.(\filter, \midGain,  midGain) };
    if(highGain.notNil) { ~fxSetParam.(\filter, \highGain, highGain) };
    if(midFreq.notNil)  { ~fxSetParam.(\filter, \midFreq,  midFreq) };
};


// =====================================================================
//   ROTEAMENTO MODULAR — source picker, channel routing, master send
// =====================================================================

~fxList = [\timeStretch, \reverse, \adsr, \modulation, \filter,
           \reverb, \delay, \harmonizer];

// Opções disponíveis para source de cada efeito
~fxSourceOptions = { |fxName|
    var others = ~fxList.reject { |fx| fx == fxName };
    [\dry] ++ others
};

// Detecta ciclo: assumindo que fxName.source = newSource, percorre a
// cadeia a partir de newSource e ve se algo aponta de volta para fxName.
~detectFxCycle = { |fxName, newSource|
    var current = newSource;
    var visited = Set.new;
    var cycleFound = false;
    var maxSteps = 16;  // segurança
    if(newSource == \dry) {
        cycleFound = false;
    } {
        if(newSource == fxName) {
            cycleFound = true;
        } {
            block { |break|
                while { (current != \dry) and: { maxSteps > 0 } } {
                    if(current == fxName) {
                        cycleFound = true;
                        break.value;
                    };
                    if(visited.includes(current)) { break.value };
                    visited.add(current);
                    current = (~fxRouting[current] ? IdentityDictionary.new)[\source] ? \dry;
                    maxSteps = maxSteps - 1;
                };
            };
        };
    };
    cycleFound
};

// Ordem topológica: efeitos sem dependências primeiro, depois os que
// dependem deles. Usada para reordenar synths no servidor.
~topologicalSortFx = {
    var result = List.new;
    var visited = Set.new;
    var temp = Set.new;
    var visit;
    visit = { |name|
        if(visited.includes(name).not and: { temp.includes(name).not }) {
            var source;
            temp.add(name);
            source = (~fxRouting[name] ? IdentityDictionary.new)[\source] ? \dry;
            if(~fxList.includes(source)) { visit.value(source) };
            temp.remove(name);
            visited.add(name);
            result.add(name);
        };
    };
    ~fxList.do { |fx| visit.value(fx) };
    result.array
};

// Reordena os Synths no servidor para garantir que efeito-fonte rode
// antes do efeito-destino (evita latência de 1 bloco em cadeias).
~reorderFxSynths = {
    var order = ~topologicalSortFx.value;
    var prev = nil;
    order.do { |fxName|
        var synth = ~fx[fxName];
        if(synth.notNil) {
            if(prev.notNil) { synth.moveAfter(prev) };
            prev = synth;
        };
    };
};

// Muda a fonte de um efeito. Retorna true se sucedeu, false em caso
// de ciclo detectado.
~fxSetSource = { |fxName, sourceName|
    var ok = true;
    var newBus;
    var includeMic;
    if(~fxRouting[fxName].isNil) {
        ("!! fxName desconhecido: " ++ fxName).postln;
        ok = false;
    } {
        if(~detectFxCycle.(fxName, sourceName)) {
            ("!! Ciclo detectado: " ++ fxName ++ " ← " ++ sourceName
              ++ ". Mantendo configuração anterior.").postln;
            ok = false;
        } {
            newBus = ~resolveSrcBus.(sourceName);
            // includeMic: só inclui mic se source for dry. Quando vem de
            // outro efeito, esse já incluiu o mic (se relevante).
            includeMic = if(sourceName == \dry) { 1 } { 0 };
            ~fx[fxName].set(\inBus, newBus, \includeMic, includeMic);
            ~fxRouting[fxName][\source] = sourceName;
            ~reorderFxSynths.value;
            ("fx " ++ fxName ++ " source ← " ++ sourceName
              ++ " (includeMic=" ++ includeMic ++ ")").postln;
            ~onFxRoutingChanged !? { |fn| fn.value(fxName, \source, sourceName) };
        };
    };
    ok
};

~fxSetSendToMaster = { |fxName, send|
    var s;
    if(~fx[fxName].isNil) { ^nil };
    s = if(send.asBoolean) { 1 } { 0 };
    ~fx[fxName].set(\sendToMaster, s);
    ~fxRouting[fxName][\sendToMaster] = s;
    ("fx " ++ fxName ++ " → master: " ++ (s == 1)).postln;
    ~onFxRoutingChanged !? { |fn| fn.value(fxName, \sendToMaster, s) };
};

~fxSetCh = { |fxName, chSym|
    var i;
    if(~fx[fxName].isNil) { ^nil };
    i = ~chModeToInt.(chSym);
    ~fx[fxName].set(\chMode, i);
    ~fxRouting[fxName][\chMode] = i;
    ("fx " ++ fxName ++ " channel: " ++ chSym ++ " (" ++ i ++ ")").postln;
    ~onFxRoutingChanged !? { |fn| fn.value(fxName, \chMode, i) };
};

// Reseta todos os efeitos para o roteamento padrão (DRY, →master, stereo)
~fxResetRouting = {
    ~fxList.do { |fx|
        ~fxSetSource.(fx, \dry);
        ~fxSetSendToMaster.(fx, 1);
        ~fxSetCh.(fx, \stereo);
    };
    "Roteamento de efeitos resetado para padrão paralelo.".postln;
};
