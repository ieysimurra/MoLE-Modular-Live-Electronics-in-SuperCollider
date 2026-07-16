# MoLE - Modular Live Electronics — SuperCollider

Sistema modular de *live electronics* em SuperCollider para performance em tempo real e composição de música mista instrumental. Combina processamento de microfone, looping multi-buffer, oito categorias de efeitos com roteamento modular, controle via AKAI MIDIMIX, presets persistentes e sistema de **partitura em cue list**.

> Desenvolvido no NICS (Núcleo Interdisciplinar de Comunicação Sonora) — Universidade Estadual de Campinas (UNICAMP).

![SuperCollider](https://img.shields.io/badge/SuperCollider-3.13%2B-blue)
![Plugins](https://img.shields.io/badge/sc3--plugins-required-orange)
![License](https://img.shields.io/badge/license-GPL--3.0-green)
![Version](https://img.shields.io/badge/version-1.1.0-brightgreen)

---

## Sobre

Instrumento de *live electronics* que combina três paradigmas num único ambiente:

- **Processamento ao vivo** do sinal de entrada com 8 categorias de efeitos
- **Looping e sampling** multi-buffer com duração livre
- **Partitura em cue list** para composição estruturada — cenas pré-configuradas disparadas manualmente, permitindo que o intérprete acústico conduza o andamento sem a rigidez de um cronômetro

## Características principais

### Efeitos (8 categorias)
- **Time-Stretch** (Warp1)
- **Reverse** (Latch + Sweep + BufRd)
- **ADSR** — envelope disparável
- **Modulation** — três modos: **RM** (Ring), **AM** (Amplitude), **FM** (Frequency)
- **Filter + EQ** — RHPF + RLPF + 3-band EQ
- **Reverb** (JPverb, requer sc3-plugins)
- **Delay** estéreo com feedback
- **Harmonizer** — 8 vozes com PitchShift

### Roteamento modular
- **Source picker** por efeito — cada um pode ler do sinal seco ou da saída de outro, criando topologias em série/paralelo/mistas
- **Detecção automática de ciclos** e **ordenação topológica** dos synths
- **Channel routing** (CH1/CH2/Stereo) independente por slot e por efeito

### Sampling e looping
- 8 samples com gravação press-and-hold, playback play/pause (via Mute)
- 8 loops de até 60 s com gravação manual, overdub e duração livre
- Rota **FX / RAW / BOTH** por slot, aplicada em tempo real

### Sistema de presets
- 8 presets em memória com LED de estado (vazio / salvo / ativo)
- **Banks persistentes** em `.preset` (texto plano, versionáveis)
- Captura completa: efeitos, roteamento, channel routing, globais, rotas de slots

### Partitura em cue list
- **Cenas pré-configuradas** em `.txt`, editáveis na aba MASTER
- **Disparo manual** — não há relógio automático; navegação livre entre cenas
- **Fades opcionais** por comando (`fade N`)
- **Mensagens `say`** grandes para o intérprete
- Atalhos: Espaço/F8 (próxima), F7 (anterior), F5 (dispara selecionada), Shift+1..9,0 (salto direto)

### Controle e interface
- **AKAI MIDIMIX** com *MIDI learn* e feedback de LEDs
- **GUI** de cinco abas: Master (com score) / Samples / Loops / Effects / Presets

## Requisitos

- [SuperCollider](https://supercollider.github.io/) 3.13 ou superior
- [sc3-plugins](https://github.com/supercollider/sc3-plugins) (para JPverb no Reverb)
- Interface de áudio com baixa latência (testado com Focusrite Scarlett 2i4)
- *(Opcional)* Controlador AKAI MIDIMIX

Ver [docs/INSTALL.md](docs/INSTALL.md).

## Início rápido

```bash
git clone https://github.com/<seu-usuario>/live-electronics-sc.git
cd live-electronics-sc
```

1. Abra `src/main.scd` no SuperCollider IDE
2. Execute o arquivo inteiro (Ctrl+Enter no parêntese externo)
3. Execute `~boot.value;`
4. Aba MASTER → seção SCORE → LOAD `exemplo_score` para experimentar
5. Encerrar com `~cleanup.value;`

> Ao editar qualquer módulo `.scd`, reexecute `main.scd` inteiro antes de `~boot`.

## Documentação

| Documento | Conteúdo |
|---|---|
| [INSTALL.md](docs/INSTALL.md) | Instalação de SC, sc3-plugins, áudio, MIDI |
| [USAGE.md](docs/USAGE.md) | Fluxo de trabalho, comandos, atalhos |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Buses, grupos, fluxo de sinal |
| [EFFECTS.md](docs/EFFECTS.md) | Os 8 efeitos: UGens, parâmetros |
| [SCORE.md](docs/SCORE.md) | Linguagem de partitura (cue list) |
| [MIDI_MAPPING.md](docs/MIDI_MAPPING.md) | Mapeamento da MIDIMIX |
| [ROUTING.md](docs/ROUTING.md) | Roteamento modular e channel routing |
| [PRESETS_AND_BANKS.md](docs/PRESETS_AND_BANKS.md) | Presets e banks |

## Estrutura

```
live-electronics-sc/
├── src/                    # Código-fonte (8 módulos .scd)
├── docs/                   # Documentação técnica
├── scores/                 # Partituras .txt
│   ├── exemplo_score.txt   # Modelo para começar
│   └── Wabi-sabi.txt       # Peça de referência (Ivan Simurra)
├── examples/               # Snippets e banks de exemplo
└── .github/                # Templates de issues
```

## Como citar

```bibtex
@software{simurra_live_electronics_2026,
  author       = {Simurra, Ivan Eiji},
  title        = {{Live Electronics: A Modular SuperCollider System
                   for Real-Time Performance}},
  version      = {1.1.0},
  year         = {2026},
  publisher    = {NICS/UNICAMP},
  url          = {https://github.com/<seu-usuario>/live-electronics-sc}
}
```

Ver [CITATION.cff](CITATION.cff).

## Licença

Código sob [GPL-3.0](LICENSE). Documentação em `docs/` sob CC BY 4.0.

## Agradecimentos

Desenvolvido no NICS/UNICAMP. Construído sobre [SuperCollider](https://supercollider.github.io/) e [sc3-plugins](https://github.com/supercollider/sc3-plugins).
