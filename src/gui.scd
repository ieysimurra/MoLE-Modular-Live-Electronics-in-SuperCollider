// =====================================================================
// LIVE ELECTRONICS — gui.scd
// =====================================================================
// GUI com 4 abas: Master / Samples / Loops / Efeitos.
//
// Atalhos:
//   Cmd/Ctrl+1..4   navega entre abas
//   Cmd/Ctrl+5..9   foca efeito 1..5 (aba Efeitos)
//   q w e r t y u i press/release samples 0..7 (sempre ativo)
//   1..8            toggle loop record/stop 0..7 (sempre ativo)
//
// Cores de estado dos slots:
//   empty       cinza escuro
//   recording   vermelho
//   playing     verde
//   overdubbing amarelo
//   stopped     azul
//   stopping    laranja
// =====================================================================


// ---- Paleta de cores ------------------------------------------------
~guiColors = IdentityDictionary[
    \bg          -> Color.gray(0.15),
    \panel       -> Color.gray(0.22),
    \panelLight  -> Color.gray(0.3),
    \text        -> Color.white,
    \textDim     -> Color.gray(0.7),
    \accent      -> Color(0.3, 0.5, 0.9),
    \accentDim   -> Color(0.2, 0.3, 0.5),
    \focusBorder -> Color(1.0, 0.8, 0.2),

    // Estados dos slots
    \stateEmpty       -> Color.gray(0.3),
    \stateRecording   -> Color(0.9, 0.2, 0.2),
    \statePlaying     -> Color(0.2, 0.8, 0.3),
    \stateOverdubbing -> Color(0.9, 0.8, 0.2),
    \stateStopped     -> Color(0.3, 0.5, 0.8),
    \stateStopping    -> Color(0.9, 0.5, 0.2),

    // Bypass de efeito
    \bypassOn  -> Color.gray(0.3),
    \bypassOff -> Color(0.2, 0.8, 0.3)
];


// ---- Função principal -----------------------------------------------
~buildGui = {
    var tabBtns, tabsContainer;

    ~gui = IdentityDictionary.new;
    ~gui[\tabBtns] = IdentityDictionary.new;
    ~gui[\tabViews] = IdentityDictionary.new;
    ~gui[\slotSample] = Array.fill(8, { IdentityDictionary.new });
    ~gui[\slotLoop]   = Array.fill(8, { IdentityDictionary.new });
    ~gui[\fx]         = IdentityDictionary.new;
    ~gui[\keyState]   = IdentitySet.new;   // teclas atualmente pressionadas

    // ---- Janela ----
    ~window = Window("Live Electronics — NICS/UNICAMP",
                     Rect(50, 50, 1200, 720),
                     resizable: false);
    ~window.background = ~guiColors[\bg];
    ~window.view.background = ~guiColors[\bg];

    // ---- Tab bar ----
    [\master, \samples, \loops, \effects, \presets].do { |tabName, i|
        var btn = Button()
            .states_([
                [tabName.asString.toUpper, ~guiColors[\text], ~guiColors[\panelLight]],
                [tabName.asString.toUpper, ~guiColors[\text], ~guiColors[\accent]]
            ])
            .font_(Font("Helvetica", 14, true))
            .action_({ ~switchTab.(tabName) })
            .minHeight_(40);
        ~gui[\tabBtns][tabName] = btn;
    };

    // ---- Constrói cada aba ----
    ~gui[\tabViews][\master]  = ~buildTabMaster.value;
    ~gui[\tabViews][\samples] = ~buildTabSamples.value;
    ~gui[\tabViews][\loops]   = ~buildTabLoops.value;
    ~gui[\tabViews][\effects] = ~buildTabEffects.value;
    ~gui[\tabViews][\presets] = ~buildTabPresets.value;

    // ---- Status bar ----
    ~gui[\statusText] = StaticText()
        .string_(" Pronto.")
        .background_(~guiColors[\panel])
        .stringColor_(~guiColors[\textDim])
        .font_(Font("Monaco", 11));

    // ---- Layout principal (StackLayout para alternar abas) ----
    tabsContainer = View();
    tabsContainer.layout = StackLayout(
        ~gui[\tabViews][\master],
        ~gui[\tabViews][\samples],
        ~gui[\tabViews][\loops],
        ~gui[\tabViews][\effects],
        ~gui[\tabViews][\presets]
    );
    ~gui[\tabsContainer] = tabsContainer;

    ~window.layout = VLayout(
        HLayout(
            ~gui[\tabBtns][\master],
            ~gui[\tabBtns][\samples],
            ~gui[\tabBtns][\loops],
            ~gui[\tabBtns][\effects],
            ~gui[\tabBtns][\presets]
        ),
        tabsContainer,
        ~gui[\statusText].minHeight_(24)
    );

    // ---- Listeners de estado ----
    ~onSlotStateChanged = { |kind, idx, newState|
        defer { ~updateSlotLed.(kind, idx, newState) };
    };

    // Throttling de updates da GUI de efeitos. Knobs físicos enviam muitos
    // CCs por segundo; sem throttle, a AppClock satura e a GUI fica engasgada.
    ~fxGuiThrottle = IdentityDictionary.new;
    ~fxGuiThrottleInterval = 0.033;  // ~30 fps

    ~onFxChanged = { |fxName, paramName, val|
        var key, now, last;
        // bypass é sempre imediato (raro, importante)
        if(paramName == \bypass) {
            defer { ~updateFxGui.(fxName, paramName, val) };
        } {
            key = (fxName.asString ++ "/" ++ paramName.asString).asSymbol;
            now = SystemClock.beats;
            last = ~fxGuiThrottle[key] ? 0;
            if((now - last) >= ~fxGuiThrottleInterval) {
                ~fxGuiThrottle[key] = now;
                defer { ~updateFxGui.(fxName, paramName, val) };
            };
        };
    };

    ~updateModeGui = { |newMode|
        defer { ~updateModeButtons.(newMode) };
    };

    // ---- Atalhos de teclado ----
    ~window.view.canFocus = true;
    ~window.view.keyDownAction = { |view, char, modifiers, unicode, keycode|
        ~handleKeyDown.(char, modifiers, keycode);
    };
    ~window.view.keyUpAction = { |view, char, modifiers, unicode, keycode|
        ~handleKeyUp.(char, modifiers);
    };

    // Devolve o foco ao view principal — usado após cada clique em botão
    // para que Espaço/atalhos continuem funcionando via ~handleKeyDown.
    // AppClock defer garante que o foco só é solicitado após o Qt terminar
    // de processar o clique atual, evitando "roubo" prematuro.
    ~returnFocusToMain = {
        AppClock.sched(0.05, {
            if(~window.notNil and: { ~window.view.notClosed }) {
                ~window.view.focus(true);
            };
            nil
        });
    };

    // ---- Onclose ----
    ~window.onClose = { ~window = nil };

    // ---- Aba inicial ----
    ~switchTab.(\effects);
    ~focusFx.(\timeStretch);

    ~window.front;
};


// =====================================================================
//   ABA MASTER
// =====================================================================
~buildTabMaster = {
    var view, modeButtons, knobWetDry, knobMaster, knobInput, monitorBtn;
    var labelStyle;

    labelStyle = { |s| StaticText().string_(s).align_(\center)
        .stringColor_(~guiColors[\text]).font_(Font("Helvetica", 12, true)) };

    view = View();
    view.background = ~guiColors[\bg];

    // Modos (4 botões mutex)
    modeButtons = IdentityDictionary.new;
    [\off, \live, \buffer, \both].do { |modeName|
        var btn = Button()
            .states_([
                [modeName.asString.toUpper, ~guiColors[\text], ~guiColors[\panelLight]],
                [modeName.asString.toUpper, ~guiColors[\text], ~guiColors[\accent]]
            ])
            .minHeight_(50)
            .font_(Font("Helvetica", 13, true))
            .action_({ ~setMode.(modeName) });
        modeButtons[modeName] = btn;
    };
    ~gui[\modeButtons] = modeButtons;

    // Direct Monitor (toggle): controla mic direto no output
    monitorBtn = Button()
        .states_([
            ["DIRECT MONITOR: OFF", ~guiColors[\text], ~guiColors[\panelLight]],
            ["DIRECT MONITOR: ON",  Color.black, Color(0.95, 0.55, 0.1)]
        ])
        .minHeight_(40)
        .font_(Font("Helvetica", 12, true))
        .action_({ |b| ~setMonitor.(b.value) });
    ~gui[\monitorBtn] = monitorBtn;
    ~updateMonitorGui = { |val|
        defer { ~gui[\monitorBtn].value_(val.asInteger) };
    };

    // Knobs globais
    knobWetDry = Knob().value_(0.5)
        .action_({ |k| ~setWetDry.(k.value) });
    knobMaster = Knob().value_(0.8)
        .action_({ |k| ~setMasterAmp.(k.value) });
    knobInput = Knob().value_(0.25)  // gain 1.0 = 0.25 do range 0..4
        .action_({ |k| ~setInputGain.(k.value * 4) });

    ~gui[\knobWetDry]    = knobWetDry;
    ~gui[\knobMasterAmp] = knobMaster;
    ~gui[\knobInputGain] = knobInput;

    ~updateGlobalKnob = { |name, val|
        defer {
            case
            { name == \wetDry }    { knobWetDry.value_(val) }
            { name == \masterAmp } { knobMaster.value_(val) }
            { name == \inputGain } { knobInput.value_(val / 4) };
        };
    };

    view.layout = VLayout(
        // ---- TOPO: controles clássicos da aba Master ----
        HLayout(
            // Coluna 1 — Modos
            VLayout(
                labelStyle.("MODO DE ENTRADA"),
                modeButtons[\off],
                modeButtons[\live],
                modeButtons[\buffer],
                modeButtons[\both],
                nil
            ),
            // Coluna 2 — Knobs globais + Monitor
            VLayout(
                labelStyle.("CONTROLES GLOBAIS"),
                HLayout(
                    VLayout(labelStyle.("INPUT GAIN"), knobInput.fixedSize_(80@80)),
                    VLayout(labelStyle.("WET / DRY"), knobWetDry.fixedSize_(80@80)),
                    VLayout(labelStyle.("MASTER"),    knobMaster.fixedSize_(80@80))
                ),
                monitorBtn,
                StaticText().string_("(Mic vai sempre para os efeitos; \nDIRECT MONITOR adiciona o mic\ndireto ao output sem efeitos)")
                    .stringColor_(~guiColors[\textDim])
                    .align_(\center)
                    .font_(Font("Helvetica", 10)),
                nil
            ),
            // Coluna 3 — Informações
            VLayout(
                labelStyle.("SISTEMA"),
                StaticText().string_("8 samples × 60s")
                    .stringColor_(~guiColors[\textDim]).align_(\center),
                StaticText().string_("8 loops × 60s")
                    .stringColor_(~guiColors[\textDim]).align_(\center),
                StaticText().string_("8 efeitos com roteamento modular")
                    .stringColor_(~guiColors[\textDim]).align_(\center),
                nil
            )
        ),
        // ---- METADE INFERIOR: seção SCORE ----
        ~buildScoreSection.value
    );

    view
};

~updateModeButtons = { |newMode|
    [\off, \live, \buffer, \both].do { |m|
        ~gui[\modeButtons][m].value_(if(m == newMode, 1, 0));
    };
};


// =====================================================================
//   SEÇÃO SCORE (aba Master, metade inferior)
// =====================================================================
// =====================================================================
//   SEÇÃO SCORE (aba Master, metade inferior) — modo cue list
// =====================================================================
~buildScoreSection = {
    var container, editor, statusLabel, sayLabel;
    var loadCombo, filenameField, refreshBtn, loadBtn, saveBtn;
    var parseBtn, prevBtn, goBtn, nextBtn, resetBtn;
    var sceneListView, currentSceneLabel;
    var refreshList, refreshSceneList;

    container = View();
    container.background = ~guiColors[\panel];

    // ---- Editor ----
    editor = TextView()
        .string_(
            "# Exemplo — edite ou LOAD um arquivo .txt\n"
            "title: minha peça\n"
            "composer: —\n"
            "\n"
            "[Cena 1: Início]\n"
            "mode live\n"
            "preset 0\n"
            "say Comece quando quiser\n"
            "\n"
            "[Cena 2: Transformação]\n"
            "preset 1\n"
            "fx.mix reverb 0.9 fade 3\n"
            "sample.play 0\n"
            "say Sample A retorna\n"
            "\n"
            "[Cena 3: Coda]\n"
            "master.amp 0.2 fade 8\n"
            "mode off\n"
            "say — fim —\n"
        )
        .font_(Font("Monaco", 11))
        .background_(Color(0.08, 0.08, 0.09))
        .stringColor_(~guiColors[\text])
        .tabWidth_(4);
    ~gui[\scoreEditor] = editor;

    // Handler unificado de atalhos do score. Retorna true se tratou a
    // tecla — cada widget que quer receber esses atalhos aplica esta
    // função no seu keyDownAction.
    //
    // Sobre Shift+número: em vez de comparar `char` (que muda conforme
    // o layout — no ABNT2 brasileiro Shift+2 vira "@", Shift+3 vira "#"
    // etc.), usamos o `keycode` físico da tecla, que é constante:
    //   1=49, 2=50, 3=51, 4=52, 5=53, 6=54, 7=55, 8=56, 9=57, 0=48
    // Esses são os códigos ASCII dos dígitos, também o Qt keycode das
    // teclas físicas correspondentes no teclado alfanumérico principal.
    ~scoreKeyHandler = { |char, mod, keycode|
        var hasShift = (mod & 0x20000) > 0;
        // keycodes das teclas físicas 1..9,0 (na mesma ordem da MIDIMIX/GUI)
        var sceneKeycodes = [49, 50, 51, 52, 53, 54, 55, 56, 57, 48];
        var pos, handled = false;
        case
        // Teclas de função — sempre atuam
        { keycode == 16777271 } { ~scoreFireNext.value; handled = true }  // F8
        { keycode == 16777270 } { ~scoreFirePrev.value; handled = true }  // F7
        { keycode == 16777268 } {                                          // F5
            var idx = sceneListView.value;
            if(idx.notNil) { ~scoreFireScene.(idx) };
            handled = true;
        };
        // Shift + tecla numérica física — pula direto para cena 1..10
        // (usa keycode em vez de char para funcionar em qualquer layout).
        if(handled.not and: { hasShift } and: { sceneKeycodes.includes(keycode) }) {
            pos = sceneKeycodes.indexOf(keycode);
            if(pos < ~scoreScenes.size) {
                ~scoreFireScene.(pos);
            } {
                ("SCORE: cena " ++ (pos + 1) ++ " não existe (partitura tem "
                  ++ ~scoreScenes.size ++ " cenas)").postln;
            };
            handled = true;
        };
        handled
    };

    // Aplica handler no editor (foco quando você está digitando/lendo)
    editor.keyDownAction = { |view, char, mod, unicode, keycode|
        ~scoreKeyHandler.(char, mod, keycode);
    };

    // ---- Lista de cenas (à direita) ----
    // Comportamento:
    //   • Clique único → seleciona a linha (visualmente destacada)
    //   • Duplo-clique (< 500ms entre dois cliques) → dispara a cena
    //   • Enter → dispara a cena selecionada
    //   • Shift+número, F5, F7, F8 → atalhos globais de score
    //
    // Nota técnica: NÃO usamos mouseUpAction para o clique único,
    // pois isso sobrescreve o comportamento nativo de seleção do
    // ListView (que só funciona via .action_). Detectamos duplo-clique
    // por timing: dois disparos do .action_ em menos de 500ms.
    sceneListView = ListView()
        .items_([])
        .font_(Font("Helvetica", 12, true))
        .background_(Color(0.10, 0.10, 0.12))
        .stringColor_(~guiColors[\text])
        .selectedStringColor_(Color.black)
        .hiliteColor_(Color(1, 0.85, 0.4));
    ~gui[\scoreSceneList] = sceneListView;

    // Estado para detecção de duplo-clique via timing
    ~gui[\sceneListLastClick] = 0;
    ~gui[\sceneListLastIdx] = nil;

    // .action_ dispara sempre que o usuário seleciona uma linha
    // (via clique ou setas). Se for o mesmo índice em menos de 500ms,
    // interpretamos como duplo-clique → dispara a cena.
    sceneListView.action = { |lv|
        var now = SystemClock.seconds;
        var idx = lv.value;
        var deltaT = now - (~gui[\sceneListLastClick] ? 0);
        if(idx.notNil
           and: { idx == ~gui[\sceneListLastIdx] }
           and: { deltaT < 0.5 }) {
            // Duplo-clique detectado
            ~scoreFireScene.(idx);
            ~returnFocusToMain.value;
            ~gui[\sceneListLastClick] = 0;   // reset (evita triplo-clique)
        } {
            ~gui[\sceneListLastClick] = now;
            ~gui[\sceneListLastIdx] = idx;
        };
    };

    // Atalhos dentro do ListView: teclas globais do score
    // + Espaço (avança), Enter (dispara selecionada), Backspace (volta).
    sceneListView.keyDownAction = { |lv, char, mod, unicode, keycode|
        var handled = ~scoreKeyHandler.(char, mod, keycode);
        if(handled.not) {
            case
            { char == $  }                        { ~scoreFireNext.value }
            { (char == $\r) or: { char == $\n } } {
                var idx = lv.value;
                if(idx.notNil) { ~scoreFireScene.(idx) };
            }
            { keycode == 16777219 } { ~scoreFirePrev.value };  // Backspace
        };
    };

    // Rótulos
    currentSceneLabel = StaticText().string_("cena atual: —")
        .stringColor_(Color(1, 0.85, 0.4))
        .font_(Font("Helvetica", 12, true));
    ~gui[\scoreCurrentLabel] = currentSceneLabel;

    statusLabel = StaticText().string_("● pronto")
        .stringColor_(~guiColors[\textDim])
        .font_(Font("Helvetica", 11));
    ~gui[\scoreStatusLabel] = statusLabel;

    // Mensagem grande para o intérprete (linha SAY)
    sayLabel = StaticText().string_("")
        .align_(\center)
        .stringColor_(Color(1, 0.85, 0.4))
        .font_(Font("Helvetica", 22, true))
        .minHeight_(60);
    ~gui[\scoreSayLabel] = sayLabel;

    // ---- Arquivo (load/save) ----
    loadCombo = PopUpMenu()
        .items_(["(selecione um score)"] ++ (~scoreList.value ? []))
        .font_(Font("Helvetica", 11));
    ~gui[\scoreLoadCombo] = loadCombo;

    filenameField = TextField()
        .string_("minha_peca")
        .font_(Font("Helvetica", 11));
    ~gui[\scoreFilenameField] = filenameField;

    refreshList = {
        defer {
            loadCombo.items = ["(selecione um score)"] ++ (~scoreList.value ? []);
        };
    };

    refreshBtn = Button()
        .states_([["↻", ~guiColors[\text], ~guiColors[\panelLight]]])
        .font_(Font("Helvetica", 12, true))
        .fixedWidth_(32)
        .action_({ refreshList.value });

    loadBtn = Button()
        .states_([["LOAD .txt", ~guiColors[\text], ~guiColors[\statePlaying]]])
        .font_(Font("Helvetica", 11, true))
        .action_({
            var idx = loadCombo.value;
            if(idx > 0) {
                var name = loadCombo.items[idx];
                var text = ~scoreLoadFile.(name);
                if(text.notNil) {
                    editor.string = text;
                    // No Windows/Qt, atribuir .string reseta a cor do texto
                    // (fica preto sobre fundo escuro). Reaplica explicitamente.
                    editor.stringColor = ~guiColors[\text];
                    editor.background  = Color(0.08, 0.08, 0.09);
                    filenameField.string = name;
                    ~scoreParse.(text);
                    statusLabel.string = "● carregado e parseado: " ++ name;
                };
            } { statusLabel.string = "! selecione um score na lista" };
        });

    saveBtn = Button()
        .states_([["SAVE .txt", ~guiColors[\text], ~guiColors[\accent]]])
        .font_(Font("Helvetica", 11, true))
        .action_({
            var name = filenameField.string;
            if(name.notEmpty) {
                if(~scoreSaveFile.(name, editor.string)) {
                    statusLabel.string = "● salvo: " ++ name;
                    refreshList.value;
                };
            } { statusLabel.string = "! forneça um nome" };
        });

    // ---- Botões de execução ----
    parseBtn = Button()
        .states_([["PARSE", ~guiColors[\text], ~guiColors[\panelLight]]])
        .font_(Font("Helvetica", 12, true))
        .minHeight_(30)
        .action_({
            var count = ~scoreParse.(editor.string);
            statusLabel.string = "● " ++ count ++ " cenas parseadas";
        });

    prevBtn = Button()
        .states_([["◀ PREV", ~guiColors[\text], ~guiColors[\panelLight]]])
        .font_(Font("Helvetica", 13, true))
        .minHeight_(45)
        .action_({ ~scoreFirePrev.value; ~returnFocusToMain.value });

    goBtn = Button()
        .states_([["▶ GO", Color.black, Color(1, 0.85, 0.4)]])
        .font_(Font("Helvetica", 14, true))
        .minHeight_(55)
        .action_({
            var idx = sceneListView.value;
            if(idx.notNil and: { idx >= 0 } and: { idx < ~scoreScenes.size }) {
                ~scoreFireScene.(idx);
            } { statusLabel.string = "! selecione uma cena na lista" };
            ~returnFocusToMain.value;
        });

    nextBtn = Button()
        .states_([["NEXT ▶", ~guiColors[\text], ~guiColors[\statePlaying]]])
        .font_(Font("Helvetica", 13, true))
        .minHeight_(45)
        .action_({ ~scoreFireNext.value; ~returnFocusToMain.value });

    resetBtn = Button()
        .states_([["⟲ RESET", ~guiColors[\text], ~guiColors[\panelLight]]])
        .font_(Font("Helvetica", 11))
        .minHeight_(28)
        .action_({
            ~scoreReset.value;
            sayLabel.string = "";
            sceneListView.value = 0;
            ~returnFocusToMain.value;
        });

    // Handler dos botões: score global + Espaço (avança). Cada botão
    // pode capturar o foco após clique — este handler garante que os
    // atalhos continuam funcionando mesmo com foco preso num botão.
    block { |break|
        var btnKeyHandler = { |btn, char, mod, unicode, keycode|
            var handled = ~scoreKeyHandler.(char, mod, keycode);
            if(handled.not and: { char == $  }) { ~scoreFireNext.value };
        };
        prevBtn.keyDownAction  = btnKeyHandler;
        goBtn.keyDownAction    = btnKeyHandler;
        nextBtn.keyDownAction  = btnKeyHandler;
        resetBtn.keyDownAction = btnKeyHandler;
    };

    // ---- Layout ----
    container.layout = HLayout(
        // Coluna 1 — editor + arquivo
        [VLayout(
            HLayout(
                StaticText().string_("SCORE — cue list")
                    .stringColor_(~guiColors[\text])
                    .font_(Font("Helvetica", 12, true)),
                nil,
                statusLabel
            ),
            editor,
            HLayout(
                StaticText().string_("bank:")
                    .stringColor_(~guiColors[\textDim])
                    .font_(Font("Helvetica", 10)).fixedWidth_(38),
                [loadCombo, stretch: 2],
                refreshBtn,
                StaticText().string_("nome:")
                    .stringColor_(~guiColors[\textDim])
                    .font_(Font("Helvetica", 10)).fixedWidth_(40),
                [filenameField, stretch: 1],
                loadBtn,
                saveBtn,
                parseBtn
            )
        ), stretch: 3],
        // Coluna 2 — lista de cenas + transport
        [VLayout(
            StaticText().string_("CENAS (clique = seleciona · duplo-clique / Enter / GO = dispara)")
                .stringColor_(~guiColors[\textDim])
                .font_(Font("Helvetica", 10, true)),
            [sceneListView, stretch: 3],
            currentSceneLabel,
            HLayout(prevBtn, nextBtn),
            goBtn,
            resetBtn,
            sayLabel,
            nil
        ), stretch: 2]
    );

    // ---- Listeners ----
    refreshSceneList = {
        defer {
            var names = ~scoreSceneNames.value;
            sceneListView.items = names;
            if(names.size > 0 and: { sceneListView.value.isNil }) {
                sceneListView.value = 0;
            };
        };
    };

    ~onScoreParsed = {
        refreshSceneList.value;
        defer {
            var count = ~scoreScenes.size;
            statusLabel.string = "● " ++ count ++ " cenas prontas";
            currentSceneLabel.string = "cena atual: —";
            sayLabel.string = "";
        };
    };

    ~onScoreSceneFired = { |idx, scene|
        defer {
            sceneListView.value = idx;
            currentSceneLabel.string =
                "▶ Cena " ++ (idx + 1) ++ ": " ++ scene[\name];
            statusLabel.string = "● cena " ++ (idx + 1) ++ "/" ++ ~scoreScenes.size;
        };
    };

    ~onScoreReset = {
        defer {
            currentSceneLabel.string = "cena atual: —";
            statusLabel.string = "● reset";
        };
    };

    ~onScoreSay = { |text|
        defer { sayLabel.string = text };
    };

    // Parse inicial (do texto default do editor)
    ~scoreParse.(editor.string);

    container
};
// =====================================================================
//   ABA SAMPLES (1 × 8)
// =====================================================================
~buildTabSamples = {
    var view, columns;

    view = View();
    view.background = ~guiColors[\bg];

    columns = 8.collect { |idx|
        ~buildSampleColumn.(idx);
    };

    view.layout = HLayout(*columns);
    view
};

~buildSampleColumn = { |idx|
    var colView, led, pressBtn, playBtn, durLabel, keyHint, routeBtn;
    var ampKnob, rateKnob, panKnob;
    var keys = [$q, $w, $e, $r, $t, $y, $u, $i];

    colView = View();
    colView.background = ~guiColors[\panel];

    // Header
    led = StaticText().string_(" ")
        .background_(~guiColors[\stateEmpty])
        .minHeight_(20);
    ~gui[\slotSample][idx][\led] = led;

    // Botão press-and-release para GRAVAR
    pressBtn = Button()
        .states_([
            ["PRESS to REC", ~guiColors[\text], ~guiColors[\panelLight]],
            ["REC...", ~guiColors[\text], ~guiColors[\stateRecording]]
        ])
        .font_(Font("Helvetica", 12, true))
        .minHeight_(50)
        .mouseDownAction_({ |b| ~samplePress.(idx); b.value = 1 })
        .mouseUpAction_({   |b| ~sampleRelease.(idx); b.value = 0 });
    ~gui[\slotSample][idx][\pressBtn] = pressBtn;

    // Botão PLAY / STOP (toggle) — mesma lógica do Mute na MIDIMIX.
    // States: 0 = parado (aparece PLAY), 1 = tocando (aparece STOP).
    playBtn = Button()
        .states_([
            ["▶ PLAY",  ~guiColors[\text], ~guiColors[\accent]],
            ["■ STOP",  ~guiColors[\text], ~guiColors[\statePlaying]]
        ])
        .value_(0)
        .font_(Font("Helvetica", 12, true))
        .minHeight_(35)
        .action_({ ~sampleToggle.(idx) });
    ~gui[\slotSample][idx][\playBtn] = playBtn;

    // Atalho visual
    keyHint = StaticText().string_("[" ++ keys[idx].asString ++ "]")
        .align_(\center).stringColor_(~guiColors[\textDim])
        .font_(Font("Monaco", 10));

    // Display de duração
    durLabel = StaticText().string_("0.00 s")
        .align_(\center).stringColor_(~guiColors[\textDim]);
    ~gui[\slotSample][idx][\durLabel] = durLabel;

    // Knobs
    ampKnob  = Knob().value_(0.5).fixedSize_(45@45);
    rateKnob = Knob().value_(0.5).fixedSize_(45@45);
    panKnob  = Knob().value_(0.5).fixedSize_(45@45);

    // Botão de roteamento: FX → RAW → BOTH → FX
    routeBtn = Button()
        .states_([
            ["FX",   ~guiColors[\text], ~guiColors[\accent]],
            ["RAW",  ~guiColors[\text], ~guiColors[\stateStopped]],
            ["BOTH", ~guiColors[\text], ~guiColors[\statePlaying]]
        ])
        .value_(0)  // \fx
        .font_(Font("Helvetica", 10, true))
        .minHeight_(22)
        .action_({ |b|
            var routes = [\fx, \raw, \both];
            ~sampleSetRoute.(idx, routes[b.value]);
        });
    ~gui[\slotSample][idx][\routeBtn] = routeBtn;

    // Botão de canal de entrada (stereo/ch1/ch2)
    block { |break|
        var chBtn = Button()
            .states_([
                ["STEREO", ~guiColors[\text], ~guiColors[\panelLight]],
                ["CH 1",   ~guiColors[\text], ~guiColors[\accent]],
                ["CH 2",   ~guiColors[\text], ~guiColors[\accent]]
            ])
            .value_(0)
            .font_(Font("Helvetica", 10))
            .minHeight_(22)
            .action_({ |b|
                var chs = [\stereo, \ch1, \ch2];
                ~sampleSetCh.(idx, chs[b.value]);
            });
        ~gui[\slotSample][idx][\chBtn] = chBtn;
    };

    colView.layout = VLayout(
        StaticText().string_("S " ++ idx).align_(\center)
            .stringColor_(~guiColors[\text]).font_(Font("Helvetica", 16, true)),
        led,
        pressBtn,
        playBtn,
        keyHint,
        durLabel,
        routeBtn,
        ~gui[\slotSample][idx][\chBtn],
        StaticText().string_("amp / rate / pan").align_(\center)
            .stringColor_(~guiColors[\textDim]).font_(Font("Helvetica", 9)),
        HLayout(ampKnob, rateKnob, panKnob),
        nil
    );

    colView
};


// =====================================================================
//   ABA LOOPS (1 × 8)
// =====================================================================
~buildTabLoops = {
    var view, columns;
    view = View();
    view.background = ~guiColors[\bg];
    columns = 8.collect { |idx| ~buildLoopColumn.(idx) };
    view.layout = HLayout(*columns);
    view
};

~buildLoopColumn = { |idx|
    var colView, led, durBox, recBtn, playBtn, stopBtn, dubBtn, clrBtn, routeBtn;
    var ampKnob, rateKnob, panKnob, keyHint;

    colView = View();
    colView.background = ~guiColors[\panel];

    led = StaticText().string_(" ")
        .background_(~guiColors[\stateEmpty])
        .minHeight_(20);
    ~gui[\slotLoop][idx][\led] = led;

    durBox = NumberBox().value_(4).clipLo_(0.1).clipHi_(60)
        .action_({ |n| ~loopSetDur.(idx, n.value) })
        .align_(\center);
    ~gui[\slotLoop][idx][\durBox] = durBox;

    recBtn  = Button().states_([["REC",  ~guiColors[\text], ~guiColors[\panelLight]]])
        .action_({ ~loopRecord.(idx) });
    playBtn = Button().states_([["PLAY", ~guiColors[\text], ~guiColors[\panelLight]]])
        .action_({ ~loopPlay.(idx) });
    stopBtn = Button().states_([["STOP", ~guiColors[\text], ~guiColors[\panelLight]]])
        .action_({ ~loopStop.(idx) });
    dubBtn  = Button().states_([
        ["DUB", ~guiColors[\text], ~guiColors[\panelLight]],
        ["DUB", ~guiColors[\text], ~guiColors[\stateOverdubbing]]
    ]).action_({ |b| ~loopOverdub.(idx, 1) });
    clrBtn  = Button().states_([["CLR", ~guiColors[\text], ~guiColors[\panelLight]]])
        .action_({ ~loopClear.(idx) });

    ~gui[\slotLoop][idx][\dubBtn] = dubBtn;

    // Botão de roteamento: FX → RAW → BOTH
    routeBtn = Button()
        .states_([
            ["FX",   ~guiColors[\text], ~guiColors[\accent]],
            ["RAW",  ~guiColors[\text], ~guiColors[\stateStopped]],
            ["BOTH", ~guiColors[\text], ~guiColors[\statePlaying]]
        ])
        .value_(0)  // \fx
        .font_(Font("Helvetica", 10, true))
        .minHeight_(22)
        .action_({ |b|
            var routes = [\fx, \raw, \both];
            ~loopSetRoute.(idx, routes[b.value]);
        });
    ~gui[\slotLoop][idx][\routeBtn] = routeBtn;

    // Botão de canal de entrada (stereo/ch1/ch2)
    block { |break|
        var chBtn = Button()
            .states_([
                ["STEREO", ~guiColors[\text], ~guiColors[\panelLight]],
                ["CH 1",   ~guiColors[\text], ~guiColors[\accent]],
                ["CH 2",   ~guiColors[\text], ~guiColors[\accent]]
            ])
            .value_(0)
            .font_(Font("Helvetica", 10))
            .minHeight_(22)
            .action_({ |b|
                var chs = [\stereo, \ch1, \ch2];
                ~loopSetCh.(idx, chs[b.value]);
            });
        ~gui[\slotLoop][idx][\chBtn] = chBtn;
    };

    keyHint = StaticText().string_("[" ++ (idx + 1).asString ++ "]")
        .align_(\center).stringColor_(~guiColors[\textDim])
        .font_(Font("Monaco", 10));

    ampKnob  = Knob().value_(0.5).fixedSize_(40@40)
        .action_({ |k| ~loopSetAmp.(idx, k.value * 2) });
    rateKnob = Knob().value_(0.5).fixedSize_(40@40)
        .action_({ |k| ~loopSetRate.(idx, k.value.linlin(0, 1, 0.25, 4)) });
    panKnob  = Knob().value_(0.5).fixedSize_(40@40)
        .action_({ |k| ~loopSetPan.(idx, k.value.linlin(0, 1, -1, 1)) });

    colView.layout = VLayout(
        StaticText().string_("L " ++ idx).align_(\center)
            .stringColor_(~guiColors[\text]).font_(Font("Helvetica", 16, true)),
        led,
        HLayout(StaticText().string_("dur:").stringColor_(~guiColors[\textDim]),
                durBox),
        recBtn, playBtn, stopBtn, dubBtn, clrBtn,
        routeBtn,
        ~gui[\slotLoop][idx][\chBtn],
        keyHint,
        HLayout(ampKnob, rateKnob, panKnob),
        nil
    );

    colView
};


// =====================================================================
//   ABA EFEITOS (5 colunas)
// =====================================================================
~buildTabEffects = {
    var view, columns;
    view = View();
    view.background = ~guiColors[\bg];

    columns = [
        ~buildFxColumn.(\timeStretch, "TIME-STRETCH", [
            (param: \mix,         label: "MIX",        range: [0, 2]),
            (param: \pan,         label: "PAN",        range: [-1, 1]),
            (param: \stretch,     label: "STRETCH",    range: [0.25, 4]),
            (param: \windowSize,  label: "WINDOW",     range: [0.02, 1]),
            (param: \overlaps,    label: "OVERLAPS",   range: [1, 16])
        ]),
        ~buildFxColumn.(\reverse, "REVERSE", [
            (param: \mix,        label: "MIX",        range: [0, 2]),
            (param: \pan,        label: "PAN",        range: [-1, 1]),
            (param: \segmentDur, label: "SEGMENT",    range: [0.1, 4]),
            (param: \density,    label: "DENSITY",    range: [0.25, 4])
        ]),
        ~buildFxColumn.(\adsr, "ADSR", [
            (param: \mix, label: "MIX", range: [0, 2]),
            (param: \pan, label: "PAN", range: [-1, 1]),
            (param: \atk, label: "ATK", range: [0.001, 4]),
            (param: \dec, label: "DEC", range: [0.001, 4]),
            (param: \sus, label: "SUS", range: [0, 1]),
            (param: \rel, label: "REL", range: [0.001, 8])
        ]),
        ~buildFxColumn.(\modulation, "MODULATION", [
            (param: \mix,     label: "MIX",      range: [0, 2]),
            (param: \pan,     label: "PAN",      range: [-1, 1]),
            (param: \modFreq, label: "MOD FREQ", range: [1, 5000], exp: true),
            (param: \depth,   label: "DEPTH",    range: [0, 1]),
            (param: \ratio,   label: "RATIO",    range: [0.1, 16], exp: true)
        ]),
        ~buildFxColumn.(\filter, "FILTER + EQ", [
            (param: \mix,      label: "MIX",     range: [0, 2]),
            (param: \pan,      label: "PAN",     range: [-1, 1]),
            (param: \lpfFreq,  label: "LPF",     range: [50, 20000], exp: true),
            (param: \hpfFreq,  label: "HPF",     range: [20, 10000], exp: true),
            (param: \lowGain,  label: "LOW dB",  range: [-24, 24]),
            (param: \midGain,  label: "MID dB",  range: [-24, 24]),
            (param: \highGain, label: "HIGH dB", range: [-24, 24])
        ]),
        ~buildFxColumn.(\reverb, "REVERB", [
            (param: \mix,   label: "MIX",   range: [0, 2]),
            (param: \pan,   label: "PAN",   range: [-1, 1]),
            (param: \decay, label: "DECAY", range: [0.1, 30], exp: true),
            (param: \size,  label: "SIZE",  range: [0.5, 3]),
            (param: \damp,  label: "DAMP",  range: [0, 1])
        ]),
        ~buildFxColumn.(\delay, "DELAY", [
            (param: \mix,      label: "MIX",   range: [0, 2]),
            (param: \pan,      label: "PAN",   range: [-1, 1]),
            (param: \time,     label: "TIME",  range: [0.001, 2], exp: true),
            (param: \feedback, label: "FBACK", range: [0, 0.95])
        ]),
        ~buildFxColumn.(\harmonizer, "HARMONIZER", [
            (param: \mix,    label: "MIX",    range: [0, 2]),
            (param: \pan,    label: "PAN",    range: [-1, 1]),
            (param: \voices, label: "VOICES", range: [1, 8]),
            (param: \spread, label: "SPREAD", range: [0, 12])
        ])
    ];

    view.layout = HLayout(*columns);
    view
};

~buildFxColumn = { |fxName, displayName, params|
    var colView, header, bypassBtn, adsrTrigBtn, knobsLayout, knobs, layoutItems;

    colView = View();
    colView.background = ~guiColors[\panel];
    ~gui[\fx][fxName] = IdentityDictionary.new;
    ~gui[\fx][fxName][\view] = colView;

    header = StaticText().string_(displayName).align_(\center)
        .stringColor_(~guiColors[\text]).font_(Font("Helvetica", 14, true));

    bypassBtn = Button()
        .states_([
            ["ACTIVE",  ~guiColors[\text], ~guiColors[\bypassOff]],
            ["BYPASS",  ~guiColors[\text], ~guiColors[\bypassOn]]
        ])
        .value_(~fxBypassState[fxName])
        .action_({ |b| ~fxBypass.(fxName, b.value) })
        .minHeight_(35);
    ~gui[\fx][fxName][\bypassBtn] = bypassBtn;

    // ---- Roteamento modular (source picker + master + ch) ----------
    block { |break|
        var sourceLabel, sourceMenu, sourceOptions, currentSource, sourceIdx;
        var masterBtn, chBtn, routingView, currentCh;

        sourceOptions = ~fxSourceOptions.(fxName);
        currentSource = (~fxRouting[fxName] ? ()) [\source] ? \dry;
        sourceIdx = sourceOptions.indexOf(currentSource) ? 0;

        sourceLabel = StaticText().string_("SOURCE")
            .align_(\center)
            .stringColor_(~guiColors[\textDim])
            .font_(Font("Helvetica", 9, true));

        sourceMenu = PopUpMenu()
            .items_(sourceOptions.collect(_.asString))
            .value_(sourceIdx)
            .font_(Font("Helvetica", 10, true))
            .action_({ |menu|
                var newSrc = sourceOptions[menu.value];
                var ok = ~fxSetSource.(fxName, newSrc);
                // se ciclo foi detectado, ~fxSetSource já imprimiu erro;
                // restaurar o menu para o source anterior
                if(ok.not) {
                    var actual = (~fxRouting[fxName] ? ())[\source] ? \dry;
                    defer { menu.value = sourceOptions.indexOf(actual) ? 0 };
                };
            });
        ~gui[\fx][fxName][\sourceMenu] = sourceMenu;

        masterBtn = Button()
            .states_([
                ["⛔ MASTER",  ~guiColors[\text], ~guiColors[\panelLight]],
                ["→ MASTER",  ~guiColors[\text], ~guiColors[\accent]]
            ])
            .value_((~fxRouting[fxName] ? ())[\sendToMaster] ? 1)
            .font_(Font("Helvetica", 10))
            .minHeight_(22)
            .action_({ |b| ~fxSetSendToMaster.(fxName, b.value == 1) });
        ~gui[\fx][fxName][\masterBtn] = masterBtn;

        currentCh = ~chIntToSym.((~fxRouting[fxName] ? ())[\chMode] ? 0);
        chBtn = Button()
            .states_([
                ["IN: STEREO", ~guiColors[\text], ~guiColors[\panelLight]],
                ["IN: CH1",    ~guiColors[\text], ~guiColors[\accent]],
                ["IN: CH2",    ~guiColors[\text], ~guiColors[\accent]]
            ])
            .value_(~chModeToInt.(currentCh))
            .font_(Font("Helvetica", 10))
            .minHeight_(22)
            .action_({ |b|
                var newCh = ~chIntToSym.(b.value);
                ~fxSetCh.(fxName, newCh);
            });
        ~gui[\fx][fxName][\chBtn] = chBtn;

        // Dropdown MODE específico para o efeito modulation
        if(fxName == \modulation) {
            var modeLabel, modeMenu, modeNames, currentMode;
            modeNames = ["RM (Ring)", "AM (Amplitude)", "FM (Freq)"];
            currentMode = (~fxParamState[\modulation] ? ())[\mode] ? 0;
            modeLabel = StaticText().string_("MODE")
                .align_(\center)
                .stringColor_(~guiColors[\textDim])
                .font_(Font("Helvetica", 9, true));
            modeMenu = PopUpMenu()
                .items_(modeNames)
                .value_(currentMode.asInteger)
                .font_(Font("Helvetica", 10, true))
                .action_({ |menu|
                    ~fxSetParam.(\modulation, \mode, menu.value);
                });
            ~gui[\fx][fxName][\modeMenu] = modeMenu;

            routingView = VLayout(
                sourceLabel,
                sourceMenu,
                masterBtn,
                chBtn,
                modeLabel,
                modeMenu
            );
        } {
            routingView = VLayout(
                sourceLabel,
                sourceMenu,
                masterBtn,
                chBtn
            );
        };
        ~gui[\fx][fxName][\routingLayout] = routingView;
    };

    // Knobs por parâmetro
    knobs = IdentityDictionary.new;
    knobsLayout = params.collect { |p|
        var paramName = p[\param];
        var range = p[\range];
        var exp = p[\exp] ? false;
        var initVal = ~fxParamState[fxName][paramName] ? range[0];
        var initNorm = if(exp) {
            (initVal / range[0]).log / (range[1] / range[0]).log
        } {
            initVal.linlin(range[0], range[1], 0, 1)
        };
        var knob = Knob().value_(initNorm).fixedSize_(50@50)
            .action_({ |k|
                var realVal = if(exp) {
                    range[0] * ((range[1] / range[0]) ** k.value)
                } {
                    k.value.linlin(0, 1, range[0], range[1])
                };
                ~dispatchFxParam.(fxName, paramName, realVal);
            });
        knobs[paramName] = (knob: knob, range: range, exp: exp);
        VLayout(
            StaticText().string_(p[\label]).align_(\center)
                .stringColor_(~guiColors[\textDim])
                .font_(Font("Helvetica", 10)),
            knob
        )
    };
    ~gui[\fx][fxName][\knobs] = knobs;

    // Botão extra para ADSR trigger
    if(fxName == \adsr) {
        adsrTrigBtn = Button()
            .states_([["TRIGGER", ~guiColors[\text], ~guiColors[\accent]]])
            .action_({ ~fxAdsrTrig.(0.5) })
            .minHeight_(30);
        ~gui[\fx][fxName][\trigBtn] = adsrTrigBtn;
    };

    // Constrói array de itens antes para evitar problemas com if/splat
    layoutItems = [header, bypassBtn,
                   ~gui[\fx][fxName][\routingLayout]] ++ knobsLayout;
    if(adsrTrigBtn.notNil) { layoutItems = layoutItems.add(adsrTrigBtn) };
    layoutItems = layoutItems.add(nil);  // spacer no final

    colView.layout = VLayout(*layoutItems);

    colView
};


// Dispatcher genérico de parâmetros de efeito (chamado pelos knobs)
~dispatchFxParam = { |fxName, paramName, val|
    if(paramName == \mix) {
        ~fxMix.(fxName, val);
    } {
        ~fxSetParam.(fxName, paramName, val);
    };
};


// =====================================================================
//   ABA PRESETS / CENAS (8 slots)
// =====================================================================
~buildTabPresets = {
    var view, slotViews, bankHeader, bankCombo, bankNameField,
        bankSaveBtn, bankLoadBtn, bankDeleteBtn, bankRefreshBtn,
        statusText, refreshList;
    view = View();
    view.background = ~guiColors[\bg];
    ~gui[\presetSlot] = Array.fill(~presetCount, { IdentityDictionary.new });

    // ---- barra superior: controles de bank em arquivo ---------------
    bankCombo = PopUpMenu()
        .items_(["(selecione um bank)"] ++ ~bankList.value)
        .font_(Font("Helvetica", 11));
    ~gui[\bankCombo] = bankCombo;

    bankNameField = TextField()
        .string_("meuBank")
        .font_(Font("Helvetica", 11));
    ~gui[\bankNameField] = bankNameField;

    statusText = StaticText().string_("")
        .stringColor_(~guiColors[\textDim])
        .font_(Font("Helvetica", 10));
    ~gui[\bankStatus] = statusText;

    refreshList = {
        defer {
            var list = ~bankList.value;
            bankCombo.items = ["(selecione um bank)"] ++ list;
        };
    };

    bankSaveBtn = Button()
        .states_([["SAVE BANK", ~guiColors[\text], ~guiColors[\accent]]])
        .font_(Font("Helvetica", 11, true))
        .minHeight_(28)
        .action_({
            var name = bankNameField.string;
            if(name.notEmpty) {
                if(~bankSave.(name)) {
                    statusText.string = "bank '" ++ name ++ "' salvo";
                    refreshList.value;
                } { statusText.string = "ERRO ao salvar" };
            } { statusText.string = "digite um nome para o bank" };
        });

    bankLoadBtn = Button()
        .states_([["LOAD BANK", ~guiColors[\text], ~guiColors[\statePlaying]]])
        .font_(Font("Helvetica", 11, true))
        .minHeight_(28)
        .action_({
            var idx = bankCombo.value;
            if(idx > 0) {
                var name = bankCombo.items[idx];
                if(~bankLoad.(name)) {
                    statusText.string = "bank '" ++ name ++ "' carregado";
                    bankNameField.string = name;
                } { statusText.string = "ERRO ao carregar" };
            } { statusText.string = "selecione um bank na lista" };
        });

    bankDeleteBtn = Button()
        .states_([["DELETE", ~guiColors[\text], ~guiColors[\bypassOn]]])
        .font_(Font("Helvetica", 10))
        .minHeight_(28)
        .action_({
            var idx = bankCombo.value;
            if(idx > 0) {
                var name = bankCombo.items[idx];
                if(~bankDelete.(name)) {
                    statusText.string = "bank '" ++ name ++ "' apagado";
                    refreshList.value;
                };
            };
        });

    bankRefreshBtn = Button()
        .states_([["↻", ~guiColors[\text], ~guiColors[\panelLight]]])
        .font_(Font("Helvetica", 12, true))
        .minHeight_(28)
        .action_({ refreshList.value; statusText.string = "lista atualizada" });

    bankHeader = View();
    bankHeader.background = ~guiColors[\panel];
    bankHeader.layout = HLayout(
        StaticText().string_("BANK:")
            .stringColor_(~guiColors[\textDim])
            .font_(Font("Helvetica", 10, true))
            .fixedWidth_(50),
        [bankCombo, stretch: 2],
        bankRefreshBtn,
        StaticText().string_("nome:")
            .stringColor_(~guiColors[\textDim])
            .font_(Font("Helvetica", 10))
            .fixedWidth_(38),
        [bankNameField, stretch: 1],
        bankSaveBtn,
        bankLoadBtn,
        bankDeleteBtn,
        [statusText, stretch: 1]
    );

    // ---- slots dos 8 presets ----------------------------------------
    slotViews = ~presetCount.collect { |idx| ~buildPresetSlot.(idx) };

    view.layout = VLayout(
        bankHeader,
        HLayout(*slotViews)
    );
    view
};

~buildPresetSlot = { |idx|
    var colView, header, statusLed, statusLabel, nameField, saveBtn, loadBtn, clearBtn;

    colView = View();
    colView.background = ~guiColors[\panel];

    header = StaticText().string_("P " ++ (idx + 1))
        .align_(\center)
        .stringColor_(~guiColors[\text])
        .font_(Font("Helvetica", 16, true));

    // LED de status: cinza=vazio, verde=salvo, laranja=ativo
    statusLed = StaticText().string_(" ")
        .background_(~guiColors[\stateEmpty])
        .minHeight_(20);
    ~gui[\presetSlot][idx][\led] = statusLed;

    statusLabel = StaticText().string_("empty")
        .align_(\center)
        .stringColor_(~guiColors[\textDim])
        .font_(Font("Helvetica", 10));
    ~gui[\presetSlot][idx][\statusLabel] = statusLabel;

    // Campo editável de nome do preset.
    // keyUpAction garante que ~presets[idx][\name] é atualizado a cada
    // tecla (action_ só dispararia em Enter, perdendo o nome se o usuário
    // só clicar fora do campo).
    nameField = TextField()
        .string_(~presets[idx][\name])
        .font_(Font("Helvetica", 11))
        .keyUpAction_({ |tf|
            ~presets[idx][\name] = tf.string;
        })
        .action_({ |tf|
            ~presets[idx][\name] = tf.string;
        });
    ~gui[\presetSlot][idx][\nameField] = nameField;

    saveBtn = Button()
        .states_([["SAVE", ~guiColors[\text], ~guiColors[\accent]]])
        .font_(Font("Helvetica", 12, true))
        .minHeight_(40)
        .action_({ ~presetSave.(idx) });

    loadBtn = Button()
        .states_([["LOAD", ~guiColors[\text], ~guiColors[\statePlaying]]])
        .font_(Font("Helvetica", 12, true))
        .minHeight_(40)
        .action_({ ~presetLoad.(idx) });

    clearBtn = Button()
        .states_([["CLR", ~guiColors[\text], ~guiColors[\panelLight]]])
        .font_(Font("Helvetica", 10))
        .minHeight_(22)
        .action_({ ~presetClear.(idx) });

    colView.layout = VLayout(
        header,
        statusLed,
        statusLabel,
        StaticText().string_("nome:")
            .stringColor_(~guiColors[\textDim])
            .font_(Font("Helvetica", 9)),
        nameField,
        saveBtn,
        loadBtn,
        clearBtn,
        nil
    );

    colView
};


// Listener — chamado quando preset é salvo, carregado, desativado ou limpo
~onPresetChanged = { |idx, kind|
    defer {
        var slotGui = ~gui[\presetSlot] !? { |arr| arr[idx] };
        if(slotGui.notNil) {
            // LED com 3 estados:
            //   ATIVO (este preset está carregado)        — laranja
            //   SALVO mas não ativo                       — verde
            //   VAZIO                                     — cinza
            if(slotGui[\led].notNil) {
                var col = if(~activePreset == idx) {
                    ~guiColors[\stateRecording]
                } {
                    if(~presets[idx][\saved],
                       ~guiColors[\statePlaying],
                       ~guiColors[\stateEmpty])
                };
                slotGui[\led].background_(col);
            };
            if(slotGui[\statusLabel].notNil) {
                slotGui[\statusLabel].string_(
                    if(~activePreset == idx, "● ACTIVE",
                       if(~presets[idx][\saved], "saved", "empty"))
                );
            };
            if(slotGui[\nameField].notNil and: { kind == \renamed }) {
                slotGui[\nameField].string_(~presets[idx][\name]);
            };
        };
        // depois de LOAD: refresh GUI inteira dos efeitos
        if(kind == \loaded) {
            ~refreshAllFxGui.value;
        };
        // Se estamos na aba presets, atualiza LEDs físicos da MIDIMIX
        if(~state[\activeTab] == \presets) {
            ~syncMidiLedsForTab !? { |fn| fn.value(\presets) };
        };
    };
};


// Força sincronização da GUI com o estado atual de todos os efeitos
~refreshAllFxGui = {
    var fxList = [\timeStretch, \reverse, \adsr, \modulation, \filter,
                  \reverb, \delay, \harmonizer];
    fxList.do { |fxName|
        var fxGui = ~gui[\fx][fxName];
        var routing = ~fxRouting[fxName] ? ();
        // bypass
        ~updateFxGui.(fxName, \bypass, ~fxBypassState[fxName] ? 1);
        // params
        ~fxParamState[fxName] !? { |params|
            params.keysValuesDo { |k, v|
                ~updateFxGui.(fxName, k, v);
            };
        };
        // source picker
        if(fxGui.notNil and: { fxGui[\sourceMenu].notNil }) {
            var src = routing[\source] ? \dry;
            var opts = ~fxSourceOptions.(fxName);
            var idx = opts.indexOf(src) ? 0;
            fxGui[\sourceMenu].value = idx;
        };
        // → master
        if(fxGui.notNil and: { fxGui[\masterBtn].notNil }) {
            fxGui[\masterBtn].value = (routing[\sendToMaster] ? 1).asInteger;
        };
        // channel
        if(fxGui.notNil and: { fxGui[\chBtn].notNil }) {
            fxGui[\chBtn].value = (routing[\chMode] ? 0).asInteger;
        };
        // mode (apenas para modulation)
        if(fxName == \modulation and: { fxGui.notNil } and: { fxGui[\modeMenu].notNil }) {
            fxGui[\modeMenu].value = ((~fxParamState[\modulation] ? ())[\mode] ? 0).asInteger;
        };
    };
    // botões de roteamento dos slots
    ~loopSlots.do { |slot, i|
        var slotGui = ~gui[\slotLoop][i];
        if(slotGui.notNil) {
            var btn = slotGui[\routeBtn];
            var ch  = slotGui[\chBtn];
            var routes = [\fx, \raw, \both];
            var chs    = [\stereo, \ch1, \ch2];
            var rIdx = routes.indexOf(slot[\route] ? \fx);
            var cIdx = chs.indexOf(slot[\inputCh] ? \stereo);
            if(btn.notNil and: { rIdx.notNil }) { btn.value_(rIdx) };
            if(ch.notNil  and: { cIdx.notNil }) { ch.value_(cIdx) };
        };
    };
    ~sampleSlots.do { |slot, i|
        var slotGui = ~gui[\slotSample][i];
        if(slotGui.notNil) {
            var btn = slotGui[\routeBtn];
            var ch  = slotGui[\chBtn];
            var routes = [\fx, \raw, \both];
            var chs    = [\stereo, \ch1, \ch2];
            var rIdx = routes.indexOf(slot[\route] ? \fx);
            var cIdx = chs.indexOf(slot[\inputCh] ? \stereo);
            if(btn.notNil and: { rIdx.notNil }) { btn.value_(rIdx) };
            if(ch.notNil  and: { cIdx.notNil }) { ch.value_(cIdx) };
        };
    };
};


// =====================================================================
//   ATUALIZAÇÃO DA GUI EM RESPOSTA A MUDANÇAS DE ESTADO
// =====================================================================

~updateSlotLed = { |kind, idx, newState|
    var slotGui = if(kind == \sample) { ~gui[\slotSample][idx] } { ~gui[\slotLoop][idx] };
    var colorKey = switch(newState,
        \empty,       \stateEmpty,
        \recording,   \stateRecording,
        \stopping,    \stateStopping,
        \playing,     \statePlaying,
        \overdubbing, \stateOverdubbing,
        \stopped,     \stateStopped,
        \recorded,    \stateStopped,  // sample gravado, aguardando play
        \ready,       \stateStopped,
        \stateEmpty);
    if(slotGui[\led].notNil) {
        slotGui[\led].background_(~guiColors[colorKey]);
    };
    // Atualiza display de duração
    if(kind == \sample and: { slotGui[\durLabel].notNil }) {
        var frames = ~sampleSlots[idx][\frames];
        slotGui[\durLabel].string_((frames / s.sampleRate).round(0.01).asString ++ " s");
    };
    // Sincroniza estado do botão PLAY/STOP do sample
    if(kind == \sample and: { slotGui[\playBtn].notNil }) {
        slotGui[\playBtn].value_(if(newState == \playing, 1, 0));
    };
    // Atualiza dubBtn nos loops
    if(kind == \loop and: { slotGui[\dubBtn].notNil }) {
        slotGui[\dubBtn].value_(if(newState == \overdubbing, 1, 0));
    };
    // Sincroniza LED MIDI
    ~syncMidiLedForSlot !? { |fn| fn.value(kind, idx, newState) };
};

~updateFxGui = { |fxName, paramName, val|
    try {
        var fxGui = ~gui[\fx][fxName];
        if(fxGui.notNil) {
            if(paramName == \bypass) {
                if(fxGui[\bypassBtn].notNil) {
                    var current = fxGui[\bypassBtn].value;
                    if(current != val.asInteger) {
                        fxGui[\bypassBtn].value_(val.asInteger);
                    };
                };
                ~syncMidiLedForFx !? { |fn| fn.value(fxName, val) };
            } {
                if(fxGui[\knobs].notNil and: { fxGui[\knobs][paramName].notNil }) {
                    var entry = fxGui[\knobs][paramName];
                    var range = entry[\range];
                    var exp = entry[\exp];
                    var norm = if(exp) {
                        (val / range[0]).log / (range[1] / range[0]).log
                    } {
                        val.linlin(range[0], range[1], 0, 1)
                    };
                    var current = entry[\knob].value;
                    if((current - norm).abs > 0.001) {
                        entry[\knob].value_(norm.clip(0, 1));
                        entry[\knob].refresh;
                    };
                };
            };
        };
    } { |err|
        ("!! ERRO em updateFxGui (" ++ fxName ++ "." ++ paramName ++ "): " ++ err.errorString).postln;
    };
};


// =====================================================================
//   TROCA DE ABA E FOCO DE EFEITO
// =====================================================================
~switchTab = { |tabName|
    var tabOrder = [\master, \samples, \loops, \effects, \presets];
    var idx = tabOrder.indexOf(tabName);
    if(idx.isNil) { ^nil };
    ~state[\activeTab] = tabName;
    ~gui[\tabsContainer].layout.index = idx;
    tabOrder.do { |t|
        ~gui[\tabBtns][t].value_(if(t == tabName, 1, 0));
    };
    ~gui[\statusText].string_(" Aba: " ++ tabName);
    ~syncMidiLedsForTab !? { |fn| fn.value(tabName) };
};

~focusFx = { |fxName|
    var allFx = [\timeStretch, \reverse, \adsr, \modulation, \filter];
    if(allFx.includes(fxName).not) { ^nil };
    ~state[\focusedFx] = fxName;
    allFx.do { |fx|
        var fxGui = ~gui[\fx][fx];
        if(fxGui.notNil and: { fxGui[\view].notNil }) {
            fxGui[\view].background_(
                if(fx == fxName, ~guiColors[\panelLight], ~guiColors[\panel])
            );
        };
    };
    ~gui[\statusText].string_(" Efeito focado: " ++ fxName);
};


// =====================================================================
//   ATALHOS DE TECLADO
// =====================================================================
~handleKeyDown = { |char, modifiers, keycode|
    var hasMod = (modifiers & 0x40000) > 0 or: { (modifiers & 0x100000) > 0 };
    var hasShift = (modifiers & 0x20000) > 0;
    var sampleKeys = [$q, $w, $e, $r, $t, $y, $u, $i];
    var loopKeys   = [$1, $2, $3, $4, $5, $6, $7, $8];
    // Keycodes das teclas físicas 1..9,0 (constantes, layout-independent)
    var sceneKeycodes = [49, 50, 51, 52, 53, 54, 55, 56, 57, 48];
    var fxList = [\timeStretch, \reverse, \adsr, \modulation, \filter,
                  \reverb, \delay, \harmonizer];
    var handled = false;

    // ---- SCORE ----
    // Espaço → NEXT (Shift+Espaço → PREV)
    if(handled.not and: { char == $  }) {
        if(hasShift) { ~scoreFirePrev.value } { ~scoreFireNext.value };
        handled = true;
    };
    // Shift + tecla física 1..9,0 → cena 1..10 (usa keycode, não char,
    // para funcionar em teclado ABNT2 onde Shift+2="@", Shift+3="#" etc.)
    if(handled.not and: { hasShift } and: { sceneKeycodes.includes(keycode) }) {
        var pos = sceneKeycodes.indexOf(keycode);
        if(pos < ~scoreScenes.size) {
            ~scoreFireScene.(pos);
        } {
            ("SCORE: cena " ++ (pos + 1) ++ " não existe").postln;
        };
        handled = true;
    };

    // ---- Modifier + 1..4/0/5-9: trocar aba / focar efeito ----
    if(handled.not and: { hasMod }) {
        case
        { char == $1 } { ~switchTab.(\master);  handled = true }
        { char == $2 } { ~switchTab.(\samples); handled = true }
        { char == $3 } { ~switchTab.(\loops);   handled = true }
        { char == $4 } { ~switchTab.(\effects); handled = true }
        { char == $0 } { ~switchTab.(\presets); handled = true }
        { char == $5 } { ~focusFx.(fxList[0]);  handled = true }
        { char == $6 } { ~focusFx.(fxList[1]);  handled = true }
        { char == $7 } { ~focusFx.(fxList[2]);  handled = true }
        { char == $8 } { ~focusFx.(fxList[3]);  handled = true }
        { char == $9 } { ~focusFx.(fxList[4]);  handled = true };
    };

    // ---- QWERTY: press de samples ----
    if(handled.not
       and: { sampleKeys.includes(char) }
       and: { ~gui[\keyState].includes(char).not }) {
        ~gui[\keyState].add(char);
        ~samplePress.(sampleKeys.indexOf(char));
        handled = true;
    };

    // ---- 1..8 sem modificador: toggle de loops ----
    if(handled.not
       and: { hasMod.not } and: { hasShift.not }
       and: { loopKeys.includes(char) }
       and: { ~gui[\keyState].includes(char).not }) {
        ~gui[\keyState].add(char);
        ~loopToggleRecord.(loopKeys.indexOf(char));
        handled = true;
    };
    handled
};

~handleKeyUp = { |char, modifiers|
    var sampleKeys = [$q, $w, $e, $r, $t, $y, $u, $i];

    ~gui[\keyState].remove(char);

    // Release de samples
    if(sampleKeys.includes(char)) {
        ~sampleRelease.(sampleKeys.indexOf(char));
    };
};


"GUI module carregado.".postln;
