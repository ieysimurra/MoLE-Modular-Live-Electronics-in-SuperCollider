// =====================================================================
// SCORE — Cue list de execução para live electronics
// Prof. Ivan Simurra · NICS/UNICAMP
// =====================================================================
//
// Uma partitura aqui é uma LISTA DE CENAS — cada cena é um conjunto
// de comandos que configuram um estado do sistema. As cenas são
// disparadas MANUALMENTE (não há relógio automático).
//
// O intérprete conduz o andamento; a eletrônica responde por cenas
// pré-configuradas. Você pode saltar entre cenas em qualquer ordem.
//
// FORMATO
// -------
// Cabeçalho opcional (linhas antes da primeira cena):
//   title: nome da peça
//   composer: autor
//   description: descrição livre
//
// Cenas são delimitadas por linhas [Cena N: descrição] ou apenas [nome]:
//
//   [Cena 1: Início]
//   mode live
//   preset 0
//   fx.mix reverb 0.8
//   say Entrada do intérprete
//
//   [Cena 2: Transformação]
//   preset 2
//   fx.mix delay 1.2 fade 3
//   sample.play 0
//   say Gesto A retorna
//
// Comentários (#) e linhas em branco são ignorados. Comandos são
// executados na ORDEM em que aparecem dentro da cena.
//
// COMANDOS (idênticos ao GUI/MIDI)
// --------------------------------
//   mode <off|live|buffer|both>
//   preset <n>                                    (fade opcional)
//   bank <nome>
//   fx.bypass <fx> <on|off>
//   fx.mix <fx> <valor>                           [fade N]
//   fx.param <fx> <param> <valor>                 [fade N]
//   fx.source <fx> <source>
//   fx.master <fx> <on|off>
//   sample.rec <n> / sample.stop <n>
//   sample.play <n> / sample.pause <n>
//   loop.rec <n> / loop.play <n> / loop.stop <n>
//   master.amp <valor>                            [fade N]
//   wetdry <valor>                                [fade N]
//   inputgain <valor>                             [fade N]
//   say <texto...>            → mensagem para o intérprete
//
// =====================================================================


// Estado interno
~scoreScenes    = List.new;      // Lista de cenas: (name:, commands: [], line:)
~scoreCurrentIdx = nil;          // Índice da última cena disparada (nil = nenhuma)
~scoreCurrentRunId = 0;          // Id crescente de execução — usado para cancelar
                                 // Routines antigas sem .stop (que corromperia
                                 // o scheduler do AppClock). Cada nova cena
                                 // incrementa; Routines antigas verificam
                                 // e saem via break.
~scoreMeta      = ();            // metadados (title, composer, description)
~scoreErrors    = List.new;
~scoreFadeGen   = IdentityDictionary.new;  // "geração" por chave de fade
                                            // (mesma técnica de cancelamento
                                            // cooperativo dos fades)


// =====================================================================
//   PARSER
// =====================================================================

// Extrai título de um cabeçalho de cena: "[Cena 1: Início]" → "Cena 1: Início"
~scoreParseSceneHeader = { |line|
    var stripped = line.stripWhiteSpace;
    // Remove \r residual (arquivos Windows)
    while { stripped.notEmpty and:
            { (stripped.last == $\r) or: { stripped.last == $\n } } } {
        stripped = stripped[..(stripped.size - 2)];
    };
    if(stripped.beginsWith("[") and: { stripped.endsWith("]") }) {
        stripped[1..(stripped.size - 2)].stripWhiteSpace
    } { nil };
};

// Parse de uma linha de comando dentro de uma cena.
// Retorna evento (Dictionary) ou nil.
~scoreParseCommand = { |line, lineNum|
    var stripped, tokens, cmd, args, fade, fadeIdx, event;

    stripped = line.stripWhiteSpace;
    if(stripped.isEmpty or: { stripped.beginsWith("#") }) { ^nil };

    tokens = stripped.split($ ).reject(_.isEmpty);
    if(tokens.size < 1) { ^nil };
    cmd  = tokens[0].toLower.asSymbol;
    args = tokens[1..];

    // Extrai "fade N" se presente
    fade = nil;
    fadeIdx = args.indexOf("fade");
    if(fadeIdx.notNil and: { fadeIdx < (args.size - 1) }) {
        fade = args[fadeIdx + 1].asFloat;
        args = args[..(fadeIdx - 1)];
    };

    // \say concatena o restante como uma string única
    if(cmd == \say) { args = [args.join(" ")] };

    event = (cmd: cmd, args: args, fade: fade, line: lineNum, raw: stripped);
    event
};

// Detecta e processa cabeçalho "chave: valor" (title, composer, description).
// Retorna true se a linha foi consumida como cabeçalho.
~scoreTryParseMeta = { |line|
    var colonIdx, cleaned, beforeColon, key, value, isKeyValid;
    var validKeys = ["title", "composer", "description"];
    var handled = false;

    // Remove \r do fim (arquivos salvos em Windows têm \r\n)
    cleaned = line.stripWhiteSpace;
    while { cleaned.notEmpty and:
            { (cleaned.last == $\r) or: { cleaned.last == $\n } } } {
        cleaned = cleaned[..(cleaned.size - 2)];
    };

    colonIdx = cleaned.indexOf($:);
    if(colonIdx.notNil and: { colonIdx > 0 }) {
        beforeColon = cleaned[..(colonIdx - 1)].stripWhiteSpace;
        // Chave só pode ter letras, _ e -
        isKeyValid = beforeColon.notEmpty and: {
            beforeColon.every { |c|
                c.isAlpha or: { c == $_ } or: { c == $- }
            };
        };
        if(isKeyValid) {
            key = beforeColon.toLower;
            // Comparação explícita (evita problemas de identity vs equality)
            validKeys.do { |vk|
                if((vk.compare(key) == 0)) {
                    value = cleaned[(colonIdx + 1)..].stripWhiteSpace;
                    ~scoreMeta[vk.asSymbol] = value;
                    handled = true;
                };
            };
        };
    };
    handled
};

// Faz o parse do texto completo. Retorna quantidade de cenas.
~scoreParse = { |text|
    var lines, currentScene, sceneHeader, isMeta;
    ~scoreScenes.clear;
    ~scoreErrors.clear;
    ~scoreMeta = ();
    ~scoreCurrentIdx = nil;

    lines = text.split($\n);
    currentScene = nil;

    lines.do { |rawLine, i|
        var line = rawLine.stripWhiteSpace;
        var lineNum = i + 1;

        // Ignora vazios e comentários
        if(line.isEmpty.not and: { line.beginsWith("#").not }) {
            sceneHeader = ~scoreParseSceneHeader.(line);
            if(sceneHeader.notNil) {
                // Nova cena
                currentScene = (
                    name: sceneHeader,
                    commands: List.new,
                    lineNum: lineNum
                );
                ~scoreScenes.add(currentScene);
            } {
                // Verifica cabeçalho meta (só válido antes da primeira cena)
                if(currentScene.isNil) {
                    isMeta = ~scoreTryParseMeta.(line);
                    if(isMeta.not) {
                        // Comando fora de qualquer cena → cria uma cena
                        // "Setup" implícita, para compatibilidade com o
                        // formato antigo
                        currentScene = (
                            name: "Setup", commands: List.new, lineNum: lineNum
                        );
                        ~scoreScenes.add(currentScene);
                        (~scoreParseCommand.(line, lineNum)) !? { |ev|
                            currentScene[\commands].add(ev)
                        };
                    };
                } {
                    // Dentro de cena: parse como comando
                    (~scoreParseCommand.(line, lineNum)) !? { |ev|
                        currentScene[\commands].add(ev)
                    };
                };
            };
        };
    };

    ("Score parseado: " ++ ~scoreScenes.size ++ " cenas, "
     ++ ~scoreErrors.size ++ " erros.").postln;
    ~onScoreParsed !? { |fn| fn.value };
    ~scoreScenes.size
};


// =====================================================================
//   EXECUÇÃO DE COMANDOS
// =====================================================================

// Fade cooperativo: cada fade tem uma "geração" por chave. Uma nova
// chamada com a mesma chave incrementa a geração; Routines antigas
// verificam e saem via break. NÃO usamos .stop (que corrompe o
// scheduler quando há .wait pendente, gerando erro _RoutineResume).
~scoreFade = { |key, initial, target, dur, setter|
    var myGen;
    ~scoreFadeGen[key] = (~scoreFadeGen[key] ? 0) + 1;
    myGen = ~scoreFadeGen[key];
    Routine({
        var steps = (dur * 30).max(1).asInteger;
        var stepDur = dur / steps;
        block { |break|
            steps.do { |i|
                var t, v;
                // Se outra chamada com a mesma chave tomou o lugar, sai
                if(~scoreFadeGen[key] != myGen) { break.value };
                t = (i + 1) / steps;
                v = initial + ((target - initial) * t);
                defer { setter.value(v) };
                stepDur.wait;
            };
        };
    }).play(AppClock);
};

// Cancela todos os fades incrementando as gerações. Routines antigas
// detectam a mudança no próximo passo e saem. Nunca chamamos .stop.
~scoreCancelAllFades = {
    ~scoreFadeGen.keysDo { |k|
        ~scoreFadeGen[k] = (~scoreFadeGen[k] ? 0) + 1;
    };
};

// Executa um único comando (dictionary) já parseado.
~scoreExecuteCommand = { |event|
    var cmd = event[\cmd];
    var args = event[\args];
    var fade = event[\fade];

    // try envolve toda a execução: se um comando específico gerar erro
    // (ex.: argumento inválido, efeito inexistente), a exceção é
    // capturada aqui e não sobe para a Routine da cena — que continua
    // executando os comandos seguintes. Sem isso, um único erro poderia
    // quebrar a Routine e deixar o AppClock com agendamentos órfãos.
    try {
        case

    { cmd == \mode } {
        ~setMode !? { |fn| fn.value(args[0].asSymbol) };
    }

    { cmd == \preset } {
        ~presetLoad !? { |fn| fn.value(args[0].asInteger) };
    }

    { cmd == \bank } {
        ~bankLoad !? { |fn| fn.value(args[0].asString) };
    }

    { cmd == 'fx.bypass' } {
        var fxName = args[0].asSymbol;
        var on = (args[1].asString.toLower == "on");
        // "on" = efeito ativo (bypass=0)
        ~fxBypass !? { |fn| fn.value(fxName, on.not.asInteger) };
    }

    { cmd == 'fx.mix' } {
        var fxName = args[0].asSymbol;
        var target = args[1].asFloat;
        if(fade.notNil) {
            var initial = (~fxParamState[fxName] ? ())[\mix] ? 1;
            ~scoreFade.(
                ("mix_" ++ fxName).asSymbol, initial, target, fade,
                { |v| ~fxMix.(fxName, v) }
            );
        } {
            ~fxMix !? { |fn| fn.value(fxName, target) };
        };
    }

    { cmd == 'fx.param' } {
        var fxName = args[0].asSymbol;
        var paramName = args[1].asSymbol;
        var target = args[2].asFloat;
        if(fade.notNil) {
            var initial = ((~fxParamState[fxName] ? ())[paramName]) ? 0;
            ~scoreFade.(
                (fxName.asString ++ "_" ++ paramName.asString).asSymbol,
                initial, target, fade,
                { |v| ~fxSetParam.(fxName, paramName, v) }
            );
        } {
            ~fxSetParam !? { |fn| fn.value(fxName, paramName, target) };
        };
    }

    { cmd == 'fx.source' } {
        ~fxSetSource !? { |fn| fn.value(args[0].asSymbol, args[1].asSymbol) };
    }

    { cmd == 'fx.master' } {
        var on = (args[1].asString.toLower == "on");
        ~fxSetSendToMaster !? { |fn| fn.value(args[0].asSymbol, on) };
    }

    { cmd == 'sample.rec' }   { ~samplePress   !? { |fn| fn.value(args[0].asInteger) } }
    { cmd == 'sample.stop' }  {
        // Comando inteligente: se o slot está GRAVANDO, para a gravação
        // (sampleRelease); se está TOCANDO, para o playback (sampleStop).
        // Isso torna o comando mais intuitivo em partituras, onde a
        // intenção musical é geralmente "parar o sample, seja qual for
        // o estado atual".
        var slotIdx = args[0].asInteger;
        var slot = ~sampleSlots[slotIdx];
        if(slot.notNil) {
            case
            { slot[\state] == \recording } {
                ~sampleRelease !? { |fn| fn.value(slotIdx) };
            }
            { slot[\state] == \playing } {
                ~sampleStop !? { |fn| fn.value(slotIdx) };
            }
            { true } {
                // já parado, vazio ou em transição — sem efeito
                ("Sample [" ++ slotIdx ++ "] já parado (estado: "
                  ++ slot[\state] ++ ")").postln;
            };
        };
    }
    { cmd == 'sample.play' }  {
        var slotIdx = args[0].asInteger;
        var myRunId = ~scoreCurrentRunId;
        // Aguarda até 1s se o slot ainda estiver gravando/paralisando.
        // Verifica também o run-id: se outra cena substituiu esta durante
        // a espera, aborta sem disparar o play (evita comandos "atrasados"
        // executarem depois que o usuário já mudou de cena).
        block { |break|
            var tries = 50;
            while { (tries > 0)
                    and: { ~scoreCurrentRunId == myRunId }
                    and: { ~sampleSlots[slotIdx].notNil }
                    and: { (~sampleSlots[slotIdx][\state] == \recording)
                           or: { ~sampleSlots[slotIdx][\state] == \stopping } } } {
                0.02.wait;
                tries = tries - 1;
            };
        };
        // Só dispara se ainda somos a run válida
        if(~scoreCurrentRunId == myRunId) {
            ~samplePlay !? { |fn| fn.value(slotIdx) };
        };
    }
    { cmd == 'sample.pause' } { ~sampleStop    !? { |fn| fn.value(args[0].asInteger) } }

    { cmd == 'loop.rec' }  { ~loopToggleRecord !? { |fn| fn.value(args[0].asInteger) } }
    { cmd == 'loop.play' } { ~loopPlay !? { |fn| fn.value(args[0].asInteger) } }
    { cmd == 'loop.stop' } { ~loopStop !? { |fn| fn.value(args[0].asInteger) } }

    { cmd == 'master.amp' } {
        var target = args[0].asFloat;
        if(fade.notNil) {
            var initial = ~state[\masterAmp] ? 0.8;
            ~scoreFade.(\master_amp, initial, target, fade,
                { |v| ~setMasterAmp.(v) });
        } {
            ~setMasterAmp !? { |fn| fn.value(target) };
        };
    }

    { cmd == \wetdry } {
        var target = args[0].asFloat;
        if(fade.notNil) {
            var initial = ~state[\wetDry] ? 0.5;
            ~scoreFade.(\wetdry, initial, target, fade,
                { |v| ~setWetDry.(v) });
        } {
            ~setWetDry !? { |fn| fn.value(target) };
        };
    }

    { cmd == \inputgain } {
        var target = args[0].asFloat;
        if(fade.notNil) {
            var initial = ~state[\inputGain] ? 1;
            ~scoreFade.(\inputgain, initial, target, fade,
                { |v| ~setInputGain.(v) });
        } {
            ~setInputGain !? { |fn| fn.value(target) };
        };
    }

    { cmd == \say } {
        // Mensagem visual — GUI atualiza o sayLabel
        ~onScoreSay !? { |fn| fn.value(args[0].asString) };
        ("SCORE say → " ++ args[0]).postln;
    }

    {
        ("SCORE: comando desconhecido '" ++ cmd ++ "' (linha " ++ event[\line] ++ ")").postln;
    };
    } { |err|
        // Erro em comando individual — imprime mas não interrompe a cena
        ("SCORE !! erro em '" ++ cmd ++ "' (linha " ++ event[\line]
          ++ "): " ++ err.errorString).postln;
    };
};


// =====================================================================
//   DISPARO DE CENAS (interface principal)
// =====================================================================

// Dispara uma cena pelo índice (0-based). Retorna true/false.
//
// A execução ocorre dentro de uma Routine, permitindo esperar assinc
// dentro de comandos (ex.: sample.play aguarda \recorded).
//
// Cancelamento cooperativo via run-id: quando uma nova cena dispara,
// o ~scoreCurrentRunId é incrementado. A Routine antiga verifica esse
// id entre comandos e sai limpa se foi superada. NÃO chamamos .stop
// diretamente porque isso corrompe o scheduler do AppClock quando há
// .waits pendentes (gera erro '_RoutineResume').
~scoreFireScene = { |idx|
    var scene, ok = false, myRunId;
    if(idx.isNil or: { idx < 0 } or: { idx >= ~scoreScenes.size }) {
        ("!! Cena inválida: " ++ idx ++ " (total: " ++ ~scoreScenes.size ++ ")").postln;
    } {
        scene = ~scoreScenes[idx];
        ("SCORE ▶ Cena " ++ (idx + 1) ++ ": " ++ scene[\name]).postln;
        ~scoreCancelAllFades.value;
        // Incrementa run-id: Routines anteriores vão detectar e sair
        ~scoreCurrentRunId = (~scoreCurrentRunId ? 0) + 1;
        myRunId = ~scoreCurrentRunId;

        Routine({
            block { |break|
                scene[\commands].do { |ev|
                    // Se outra cena tomou nosso lugar, sai silenciosamente
                    if(~scoreCurrentRunId != myRunId) { break.value };
                    ~scoreExecuteCommand.(ev);
                };
                // Só marca como cena atual se ainda somos a run válida
                if(~scoreCurrentRunId == myRunId) {
                    ~scoreCurrentIdx = idx;
                    ~onScoreSceneFired !? { |fn| fn.value(idx, scene) };
                };
            };
        }).play(AppClock);
        ok = true;
    };
    ok
};

// Dispara pela posição relativa. next / prev / first / last.
~scoreFireNext = {
    var next = (~scoreCurrentIdx ? -1) + 1;
    if(next < ~scoreScenes.size) { ~scoreFireScene.(next) } {
        "SCORE: já está na última cena.".postln;
    };
};

~scoreFirePrev = {
    var prev = (~scoreCurrentIdx ? 0) - 1;
    if(prev >= 0) { ~scoreFireScene.(prev) } {
        "SCORE: já está na primeira cena.".postln;
    };
};

~scoreFireFirst = {
    if(~scoreScenes.size > 0) { ~scoreFireScene.(0) };
};

~scoreFireLast = {
    if(~scoreScenes.size > 0) { ~scoreFireScene.(~scoreScenes.size - 1) };
};

// Reset: cancela fades e invalida a Routine em execução (sem chamar
// .stop nela, para não corromper o scheduler). A Routine detecta a
// mudança de run-id e sai naturalmente.
~scoreReset = {
    ~scoreCancelAllFades.value;
    ~scoreCurrentRunId = (~scoreCurrentRunId ? 0) + 1;
    ~scoreCurrentIdx = nil;
    ~onScoreReset !? { |fn| fn.value };
    "SCORE reset (ponteiro limpo, cenas mantidas).".postln;
};


// =====================================================================
//   IO — carregar / salvar arquivo
// =====================================================================

// Diretório de scores: fica dentro do próprio projeto para que os
// arquivos .txt sejam versionáveis junto com o código.
// ~projectRoot é definido em main.scd via thisProcess.nowExecutingPath.dirname
~scoreDir = (~projectRoot ? Platform.userHomeDir) +/+ "scores";

~scoreEnsureDir = {
    if(File.exists(~scoreDir).not) {
        File.mkdir(~scoreDir);
        ("Criando diretório de scores: " ++ ~scoreDir).postln;
    };
};

~scoreLoadFile = { |filename|
    var path, text;
    ~scoreEnsureDir.value;
    if(filename.asString.endsWith(".txt").not) { filename = filename ++ ".txt" };
    path = ~scoreDir +/+ filename;
    if(File.exists(path).not) {
        ("!! Arquivo não encontrado: " ++ path).postln;
        nil
    } {
        text = File.readAllString(path);
        ("Score carregado: " ++ path).postln;
        text
    };
};

~scoreSaveFile = { |filename, text|
    var path, file;
    ~scoreEnsureDir.value;
    if(filename.asString.endsWith(".txt").not) { filename = filename ++ ".txt" };
    path = ~scoreDir +/+ filename;
    file = File(path, "w");
    if(file.isOpen) {
        file.write(text);
        file.close;
        ("Score salvo: " ++ path).postln;
        true
    } {
        ("!! Não foi possível salvar: " ++ path).postln;
        false
    };
};

~scoreList = {
    ~scoreEnsureDir.value;
    (~scoreDir +/+ "*.txt").pathMatch.collect { |f|
        PathName(f).fileNameWithoutExtension
    };
};


// =====================================================================
//   HELPERS
// =====================================================================

// Retorna a cena atual (última disparada) ou nil
~scoreCurrentScene = {
    if(~scoreCurrentIdx.notNil and: { ~scoreCurrentIdx < ~scoreScenes.size }) {
        ~scoreScenes[~scoreCurrentIdx]
    } { nil };
};

// Retorna nomes de cenas (útil para GUI listar)
~scoreSceneNames = {
    ~scoreScenes.collect { |scene, i|
        (i + 1).asString ++ ". " ++ scene[\name]
    };
};

"Score module carregado (modo cue list).".postln;
