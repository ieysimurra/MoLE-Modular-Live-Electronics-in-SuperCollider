# Instalação

## 1. SuperCollider

Instale o SuperCollider 3.13+ de [supercollider.github.io](https://supercollider.github.io/downloads).

- **Windows**: instalador `.exe`
- **macOS**: `.dmg`
- **Linux**: pacote da distribuição

## 2. sc3-plugins (para o Reverb)

O Reverb usa `JPverb`, disponível apenas via sc3-plugins.

1. Baixe a release: [github.com/supercollider/sc3-plugins/releases](https://github.com/supercollider/sc3-plugins/releases)
2. Extraia para:
   - **Windows**: `%LOCALAPPDATA%\SuperCollider\Extensions`
   - **macOS**: `~/Library/Application Support/SuperCollider/Extensions`
   - **Linux**: `~/.local/share/SuperCollider/Extensions`
3. Reinicie o SC → `Language → Recompile Class Library`
4. Verifique: `JPverb.ar` no IDE não deve dar erro

> Sem sc3-plugins, todos os efeitos funcionam **exceto** o Reverb. Substitua
> `JPverb` por `GVerb` (built-in) em `src/synthdefs.scd` se preferir.

## 3. Configuração de áudio

### Windows (ASIO)

```supercollider
Server.default.options.device = "ASIO : Focusrite USB ASIO";
ServerOptions.devices;   // lista dispositivos disponíveis
```

Use driver ASIO da interface para baixa latência. Se boot demora, adicione
`scsynth.exe` às exclusões do Windows Defender.

### macOS / Linux

Geralmente funciona com o dispositivo padrão. Ajuste `sampleRate` e
`hardwareBufferSize` em `ServerOptions` se necessário.

## 4. Controlador MIDI (opcional)

Sistema mapeia a **AKAI MIDIMIX**. Conecte antes de iniciar o SC. Feche
outros programas que usam MIDI (editor da AKAI, DAWs).

Diagnóstico: `~midiSelfTest.value;`
Reconectar: `~reconnectMidi.value;`

Ver [MIDI_MAPPING.md](MIDI_MAPPING.md).

## 5. Primeiro boot

```supercollider
// 1. Abra src/main.scd
// 2. Ctrl+Enter no parêntese externo
// 3. Inicie:
~boot.value;

// Para encerrar:
~cleanup.value;
```

Se tudo correr bem, a GUI de 5 abas abre e o Post mostra a sequência de boot.
