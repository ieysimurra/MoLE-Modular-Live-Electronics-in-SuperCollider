# Presets e Banks

## Presets em memória

8 presets em memória. Cada um captura *snapshot* completo do estado:

- Parâmetros de todos os 8 efeitos (mix, pan, bypass, específicos)
- Roteamento modular (source, → master, channel)
- Globais: wetDry, masterAmp, inputGain
- Rota de saída de cada slot (fx / raw / both)
- Canal de entrada de cada slot (stereo / ch1 / ch2)
- Nome do preset

**O áudio gravado nos buffers não é salvo** — presets guardam configuração,
não conteúdo sonoro.

### GUI (aba Presets)

| LED | Texto | Significado |
|---|---|---|
| cinza | empty | vazio |
| verde | saved | salvo, não carregado |
| laranja | ● ACTIVE | atualmente carregado |

Botões: **SAVE**, **LOAD**, **CLR** e nome editável.

### MIDI (aba Presets)

| Controle | Ação |
|---|---|
| Mute coluna i | SAVE preset i |
| RecArm coluna i | LOAD preset i |

### API

```supercollider
~presetSave.(0);
~presetLoad.(0);
~presetClear.(3);
~presetName.(0, "intro");
~presetDeactivate.value;
```

## Banks — persistência em arquivo

Bank = conjunto dos 8 presets salvo em `.preset`. Permite manter
configurações de projetos distintos.

### Localização

```
<raiz do projeto>/scores/
```

Arquivos em texto plano (via `asCompileString`, recuperados com
`.interpret`). Editáveis manualmente, versionáveis, portáveis.

### GUI (barra superior da aba Presets)

- Dropdown de bank + botão **LOAD BANK**
- Campo de nome + botão **SAVE BANK**
- **DELETE** e **↻** (atualizar lista)

### API

```supercollider
~bankSave.("wabi-sabi");
~bankLoad.("wabi-sabi");
~bankList.value;
~bankDelete.("antigo");
```

## Boas práticas para composição

Ao criar presets para uma peça:

1. **Cada preset deve ser um estado completo**, não um delta. Se o
   preset 3 usa reverb+delay, os efeitos que **não** fazem parte dele
   devem estar explicitamente em bypass. Assim, ao carregar o preset 3
   depois de outro qualquer, o estado é limpo.

2. **Preset 0 como "base neutra"** — todos os efeitos em bypass,
   parâmetros conservadores. Serve de ponto de partida para tudo.

3. **Nomes descritivos** — `"solo com reverb+delay"` diz mais que
   `"preset 3"` na hora do ensaio.

4. **Um bank por peça** — versionável junto com o `.txt` da partitura.

## Compatibilidade

Banks antigos continuam carregando. Campos ausentes recebem padrão;
campos que não existem mais (ex.: `crossSynth`) são ignorados sem erro.
