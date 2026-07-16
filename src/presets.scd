// =====================================================================
// LIVE ELECTRONICS — presets.scd
// =====================================================================
// Sistema de presets/cenas. Armazena snapshots do estado atual e
// permite recuperá-los rapidamente.
//
// Estado armazenado por preset:
//   • Para cada efeito: bypass, mix, pan e parâmetros principais
//   • Para cada slot de loop/sample: route mode (\fx, \raw, \both)
//   • Globais: wetDry, masterAmp, inputGain
//   • Nome opcional do preset
//
// API:
//   ~presetSave.(0)        // salva estado atual no preset 0
//   ~presetLoad.(0)        // carrega preset 0
//   ~presetClear.(0)       // limpa preset 0
//   ~presetName.(0, "..."); // nomeia
//
// =====================================================================


~presetCount = 8;
~activePreset = nil;  // índice do preset atualmente carregado (ou nil)


~initPresets = {
    ~presets = Array.fill(~presetCount, {
        IdentityDictionary[
            \name -> "—",
            \saved -> false,
            \data -> nil
        ]
    });
    ~activePreset = nil;
    ~ensureBankDir.value;
};


// Captura o estado atual da sessão em um Dictionary
~captureState = {
    var state = IdentityDictionary.new;
    var fxList = ~fxList ? [\timeStretch, \reverse, \adsr, \modulation, \filter,
                            \reverb, \delay, \harmonizer];

    // Efeitos: bypass + todos os params espelhados + roteamento modular
    state[\fx] = IdentityDictionary.new;
    fxList.do { |fxName|
        var fxSnap = IdentityDictionary.new;
        fxSnap[\bypass] = ~fxBypassState[fxName] ? 1;
        ~fxParamState[fxName] !? { |params|
            params.keysValuesDo { |k, v| fxSnap[k] = v };
        };
        // roteamento modular
        ~fxRouting !? { |r|
            r[fxName] !? { |route|
                fxSnap[\source]       = route[\source]       ? \dry;
                fxSnap[\sendToMaster] = route[\sendToMaster] ? 1;
                fxSnap[\chMode]       = route[\chMode]       ? 0;
            };
        };
        state[\fx][fxName] = fxSnap;
    };

    // Globais
    state[\global] = IdentityDictionary[
        \wetDry    -> (~state[\wetDry] ? 0.5),
        \masterAmp -> (~state[\masterAmp] ? 0.8),
        \inputGain -> (~state[\inputGain] ? 1.0)
    ];

    // Roteamento dos slots: route + canal de entrada
    state[\loopRoute]   = ~loopSlots.collect   { |slot| slot[\route] ? \fx };
    state[\sampleRoute] = ~sampleSlots.collect { |slot| slot[\route] ? \fx };
    state[\loopCh]      = ~loopSlots.collect   { |slot| slot[\inputCh] ? \stereo };
    state[\sampleCh]    = ~sampleSlots.collect { |slot| slot[\inputCh] ? \stereo };

    state
};


// Aplica um estado capturado (sem mexer em áudio gravado nos buffers)
~applyState = { |state|
    var fxList = ~fxList ? [\timeStretch, \reverse, \adsr, \modulation, \filter,
                            \reverb, \delay, \harmonizer];
    var routingKeys = IdentitySet[\source, \sendToMaster, \chMode];

    if(state.isNil) { ^nil };

    // Efeitos: primeiro mix e params, depois bypass, depois roteamento.
    // Aplicamos roteamento por último para evitar conflitos de ordem
    // (ex.: efeito A lendo de B que ainda não tem source restaurado).
    state[\fx] !? { |fxState|
        fxList.do { |fxName|
            var fxSnap = fxState[fxName];
            if(fxSnap.notNil) {
                fxSnap[\mix] !? { |v| ~fxMix.(fxName, v) };
                fxSnap.keysValuesDo { |k, v|
                    if((k != \bypass) and: { k != \mix }
                        and: { routingKeys.includes(k).not }) {
                        ~fxSetParam.(fxName, k, v);
                    };
                };
                fxSnap[\bypass] !? { |v| ~fxBypass.(fxName, v) };
            };
        };
        // Roteamento modular: primeiro chMode (não causa ciclo),
        // sendToMaster, depois source (com proteção de ciclo)
        fxList.do { |fxName|
            var fxSnap = fxState[fxName];
            if(fxSnap.notNil) {
                fxSnap[\chMode]       !? { |v| ~fxSetCh.(fxName, ~chIntToSym.(v)) };
                fxSnap[\sendToMaster] !? { |v| ~fxSetSendToMaster.(fxName, v == 1) };
            };
        };
        fxList.do { |fxName|
            var fxSnap = fxState[fxName];
            if(fxSnap.notNil) {
                fxSnap[\source] !? { |v| ~fxSetSource.(fxName, v) };
            };
        };
    };

    // Globais
    state[\global] !? { |g|
        g[\wetDry]    !? { |v| ~setWetDry.(v) };
        g[\masterAmp] !? { |v| ~setMasterAmp.(v) };
        g[\inputGain] !? { |v| ~setInputGain.(v) };
    };

    // Roteamento de slots
    state[\loopRoute] !? { |routes|
        routes.do { |route, i|
            if(route.notNil and: { route != ~loopSlots[i][\route] }) {
                ~loopSetRoute.(i, route);
            };
        };
    };
    state[\sampleRoute] !? { |routes|
        routes.do { |route, i|
            if(route.notNil and: { route != ~sampleSlots[i][\route] }) {
                ~sampleSetRoute.(i, route);
            };
        };
    };
    state[\loopCh] !? { |chs|
        chs.do { |ch, i|
            if(ch.notNil) { ~loopSetCh.(i, ch) };
        };
    };
    state[\sampleCh] !? { |chs|
        chs.do { |ch, i|
            if(ch.notNil) { ~sampleSetCh.(i, ch) };
        };
    };

    nil
};


~presetSave = { |idx, name|
    var preset;
    if(idx < 0 or: { idx >= ~presetCount }) {
        ("!! preset idx fora do range: " ++ idx).postln;
    } {
        preset = ~presets[idx];
        preset[\data]  = ~captureState.value;
        preset[\saved] = true;
        name !? { preset[\name] = name };
        ("Preset [" ++ idx ++ "] salvo"
         ++ (if(preset[\name] != "—", { " — " ++ preset[\name] }, { "" }))).postln;
        ~onPresetChanged !? { |fn| fn.value(idx, \saved) };
    };
};

~presetLoad = { |idx|
    var preset, prevActive;
    if(idx < 0 or: { idx >= ~presetCount }) {
        ("!! preset idx fora do range: " ++ idx).postln;
    } {
        preset = ~presets[idx];
        if(preset[\saved].not or: { preset[\data].isNil }) {
            ("Preset [" ++ idx ++ "] está vazio").postln;
        } {
            prevActive = ~activePreset;
            ~activePreset = idx;
            ("Preset [" ++ idx ++ "] carregando"
             ++ (if(preset[\name] != "—", { " — " ++ preset[\name] }, { "" }))).postln;
            ~applyState.(preset[\data]);
            // Notifica GUI: o ativo mudou, atualizar LEDs dos dois (anterior e novo)
            prevActive !? { |p| ~onPresetChanged !? { |fn| fn.value(p, \deactivated) } };
            ~onPresetChanged !? { |fn| fn.value(idx, \loaded) };
        };
    };
};

// Limpa marcação de "ativo" (volta ao estado padrão)
~presetDeactivate = {
    var prev = ~activePreset;
    ~activePreset = nil;
    prev !? { |p|
        ~onPresetChanged !? { |fn| fn.value(p, \deactivated) };
        ("Preset [" ++ p ++ "] desativado").postln;
    };
};

~presetClear = { |idx|
    var preset;
    if(idx < 0 or: { idx >= ~presetCount }) { ^nil };
    preset = ~presets[idx];
    preset[\data]  = nil;
    preset[\saved] = false;
    preset[\name]  = "—";
    ("Preset [" ++ idx ++ "] limpo").postln;
    ~onPresetChanged !? { |fn| fn.value(idx, \cleared) };
};

~presetName = { |idx, name|
    if(idx < 0 or: { idx >= ~presetCount }) { ^nil };
    ~presets[idx][\name] = name.asString;
    ~onPresetChanged !? { |fn| fn.value(idx, \renamed) };
};


// =====================================================================
//   BANCO DE PRESETS — persistência em arquivo
// =====================================================================
// Um "bank" é o conjunto inteiro dos 8 presets, salvo em um arquivo .preset.
// Permite manter vários projetos diferentes e alternar entre eles.
//
// Formato do arquivo: texto plano com asCompileString, recuperável via
// .interpret. Isso permite editar o arquivo manualmente e também
// inspecioná-lo. Não usamos writeArchive para evitar dependência de
// classes específicas e problemas de portabilidade.
//
// Localização padrão (criada na primeira execução):
//   ~/Documents/SC-Live-Electronics/banks/
// =====================================================================

~bankDir = Platform.userHomeDir +/+ "Documents" +/+ "SC-Live-Electronics" +/+ "banks";

~ensureBankDir = {
    if(File.exists(~bankDir).not) {
        ("Criando diretório de banks: " ++ ~bankDir).postln;
        File.mkdir(~bankDir);
    };
    ~bankDir
};

// Converte o array ~presets para um Array puro (sem IdentityDictionary
// nested-vivas) que possa ser serializado via asCompileString
~presetsToArchive = {
    ~presets.collect { |p|
        [
            \name -> p[\name],
            \saved -> p[\saved],
            \data -> if(p[\data].notNil) { ~stateToArchive.(p[\data]) } { nil }
        ]
    }
};

// Converte um estado (IdentityDictionary) em Array de pares
~stateToArchive = { |state|
    var result = List.new;
    state.keysValuesDo { |k, v|
        var saved = case
            { v.isKindOf(IdentityDictionary) } { ~stateToArchive.(v) }
            { v.isKindOf(Dictionary) } { ~stateToArchive.(v) }
            { v };
        result.add(k -> saved);
    };
    result.array
};

// Reconstrói ~presets de um array recuperado de arquivo
~presetsFromArchive = { |archive|
    archive.do { |p, i|
        var dict = IdentityDictionary.new;
        p.do { |pair| dict.put(pair.key, pair.value) };
        if(i < ~presetCount) {
            ~presets[i][\name]  = dict[\name] ? "—";
            ~presets[i][\saved] = dict[\saved] ? false;
            ~presets[i][\data]  = if(dict[\data].notNil) {
                ~stateFromArchive.(dict[\data])
            } { nil };
        };
    };
};

// Reconstrói uma IdentityDictionary aninhada a partir de array de pares
~stateFromArchive = { |archive|
    var dict = IdentityDictionary.new;
    archive.do { |pair|
        var v = pair.value;
        // Se valor é Array de pares (subdicionário), reconstrói recursivamente
        if(v.isKindOf(Array) and: { v.size > 0 } and: { v[0].isKindOf(Association) }) {
            v = ~stateFromArchive.(v);
        };
        dict.put(pair.key, v);
    };
    dict
};

// Salva todos os 8 presets no arquivo bankName.preset
~bankSave = { |bankName|
    var path, archive, file;
    bankName = bankName.asString;
    if(bankName.endsWith(".preset").not) { bankName = bankName ++ ".preset" };
    ~ensureBankDir.value;
    path = ~bankDir +/+ bankName;
    archive = ~presetsToArchive.value;
    file = File(path, "w");
    if(file.isOpen) {
        file.write(archive.asCompileString);
        file.close;
        ("Bank salvo: " ++ path).postln;
        true
    } {
        ("!! Não foi possível escrever bank: " ++ path).postln;
        false
    };
};

// Carrega um bank do arquivo, sobrescrevendo todos os 8 presets em memória
~bankLoad = { |bankName|
    var path, str, archive;
    bankName = bankName.asString;
    if(bankName.endsWith(".preset").not) { bankName = bankName ++ ".preset" };
    path = ~bankDir +/+ bankName;
    if(File.exists(path).not) {
        ("!! Bank não encontrado: " ++ path).postln;
        false
    } {
        str = File.readAllString(path);
        archive = str.interpret;
        if(archive.isKindOf(Array)) {
            ~presetsFromArchive.(archive);
            ~activePreset = nil;
            ("Bank carregado: " ++ path).postln;
            // Refresh GUI de todos os slots de preset
            ~presetCount.do { |i|
                ~onPresetChanged !? { |fn| fn.value(i, \bankLoaded) };
            };
            true
        } {
            ("!! Arquivo malformado: " ++ path).postln;
            false
        };
    };
};

// Lista todos os banks disponíveis no diretório
~bankList = {
    var files;
    ~ensureBankDir.value;
    files = (~bankDir +/+ "*.preset").pathMatch;
    files.collect { |f| PathName(f).fileNameWithoutExtension };
};

// Apaga um bank do disco
~bankDelete = { |bankName|
    var path;
    bankName = bankName.asString;
    if(bankName.endsWith(".preset").not) { bankName = bankName ++ ".preset" };
    path = ~bankDir +/+ bankName;
    if(File.exists(path)) {
        File.delete(path);
        ("Bank apagado: " ++ path).postln;
        true
    } {
        ("!! Bank não existe: " ++ path).postln;
        false
    };
};


"Presets module carregado.".postln;
