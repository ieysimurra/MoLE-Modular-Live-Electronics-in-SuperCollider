// =====================================================================
// LIVE ELECTRONICS — synthdefs.scd
// =====================================================================
// Todos os SynthDefs do sistema. Define ~loadSynthDefs.
// =====================================================================

~loadSynthDefs = {

    // ---- I/O --------------------------------------------------------
    //
    // inputStage:
    //   • Mic sempre vai para micBus quando gate=1 (alimenta os efeitos)
    //   • Mic vai para rawBus apenas se monitor=1 também (direct monitoring)
    //   • Por padrão monitor=0: sem direct monitoring, mic só é ouvido via efeitos
    //
    SynthDef(\inputStage, { |inBus = 0, rawBus, micBus, gate = 0, monitor = 0, gain = 1.0|
        var sig, micEnv, monEnv;
        sig = SoundIn.ar([inBus, inBus + 1]) * gain;
        micEnv = Lag.kr(gate, 0.05);
        monEnv = Lag.kr(monitor, 0.05);
        Out.ar(micBus, sig * micEnv);
        Out.ar(rawBus, sig * micEnv * monEnv);
    }).add;

    // masterStage: mistura wet (sinal processado) com raw (slots em modo RAW
    // ou BOTH, mais o direct monitor do mic). wetDry faz o crossfade entre
    // os dois caminhos. O sourceBus NÃO entra aqui — ele é exclusivamente
    // entrada dos efeitos. Isso evita que slots em modo FX vazem o sinal
    // bruto para a saída.
    SynthDef(\masterStage, { |fxBus, rawBus, wetDry = 0.5, amp = 0.8|
        var wet, raw, mix;
        wet = In.ar(fxBus, 2);
        raw = In.ar(rawBus, 2);
        mix = XFade2.ar(raw, wet, wetDry.linlin(0, 1, -1, 1));
        mix = Limiter.ar(mix * amp, 0.98, 0.01);
        Out.ar(0, mix);
    }).add;

    // ---- CAPTURA ----------------------------------------------------
    // chMode: 0 = estéreo (ambos canais), 1 = só ch1 (replicado), 2 = só ch2 (replicado)
    SynthDef(\sampleRecorder, { |inBus = 0, bufnum, gate = 1, slotId = 0, chMode = 0|
        var ch1, ch2, sig, pos, env, gateClosed;
        ch1 = SoundIn.ar(inBus);
        ch2 = SoundIn.ar(inBus + 1);
        sig = [
            Select.ar(chMode, [ch1, ch1, ch2]),
            Select.ar(chMode, [ch2, ch1, ch2])
        ];
        pos = Phasor.ar(0, BufRateScale.kr(bufnum), 0, BufFrames.kr(bufnum));
        env = EnvGen.kr(Env.asr(0.005, 1, 0.005), gate);
        BufWr.ar(sig * env, bufnum, pos);
        gateClosed = Trig1.kr(gate < 0.5, 0.001);
        SendReply.kr(gateClosed, '/sampleRecorded', [slotId, A2K.kr(pos)]);
        FreeSelf.kr(TDelay.kr(gateClosed, 0.05));
    }).add;

    SynthDef(\loopRecorder, { |inBus = 0, bufnum, slotId = 0, gate = 1, maxDur = 60,
                                chMode = 0|
        var ch1, ch2, sig, pos, env, gateClose, timeoutTrig, finalTrig;
        ch1 = SoundIn.ar(inBus);
        ch2 = SoundIn.ar(inBus + 1);
        sig = [
            Select.ar(chMode, [ch1, ch1, ch2]),
            Select.ar(chMode, [ch2, ch1, ch2])
        ];
        pos = Phasor.ar(0, BufRateScale.kr(bufnum), 0, BufFrames.kr(bufnum));
        env = EnvGen.kr(Env.asr(0.005, 1, 0.005), gate);
        BufWr.ar(sig * env, bufnum, pos);
        gateClose   = Done.kr(env);
        timeoutTrig = Done.kr(Line.kr(0, 1, maxDur));
        finalTrig   = gateClose + timeoutTrig;
        SendReply.kr(finalTrig, '/loopRecorded', [slotId, A2K.kr(pos)]);
        FreeSelf.kr(TDelay.kr(finalTrig, 0.05));
    }).add;

    // ---- PLAYBACK ---------------------------------------------------
    // outFxBus: vai pro sourceBus → passa pelos efeitos.
    // outRawBus: vai pro rawBus → direto ao master, sem efeitos.
    // sendFx/sendRaw: 0..1 (1 = sinal completo, 0 = silenciado para esse caminho).
    SynthDef(\sampleOneShot, { |bufnum, outFxBus, outRawBus, rate = 1, amp = 1, pan = 0,
                               durFrames = 44100, sendFx = 1, sendRaw = 0|
        var sig, dur, env, panned;
        dur = (durFrames / BufSampleRate.kr(bufnum)) / rate.abs.max(0.01);
        env = EnvGen.kr(
            Env([1, 1, 0], [(dur - 0.02).max(0.001), 0.02]),
            doneAction: 2
        );
        sig = PlayBuf.ar(2, bufnum, BufRateScale.kr(bufnum) * rate, loop: 0);
        panned = Balance2.ar(sig[0], sig[1], pan, amp * env);
        Out.ar(outFxBus,  panned * sendFx.lag(0.02));
        Out.ar(outRawBus, panned * sendRaw.lag(0.02));
    }).add;

    // Sample controlado por gate: toca até acabar OU até gate=0 (stop suave)
    // Usado quando o Mute atua como play/pause em vez de re-trigger.
    // Não usa loop: ao chegar no fim, para. Se receber gate=0 antes, faz
    // release curto e sai.
    SynthDef(\sampleVoice, { |bufnum, outFxBus, outRawBus, rate = 1, amp = 1, pan = 0,
                             durFrames = 44100, gate = 1,
                             sendFx = 1, sendRaw = 0|
        var sig, dur, doneEnv, gateEnv, env, panned;
        dur = (durFrames / BufSampleRate.kr(bufnum)) / rate.abs.max(0.01);
        // Envelope de duração natural. doneAction 2 = libera o Synth
        // quando chega ao fim do sample. Sem isso, o Synth ficaria vivo
        // com envelope em zero, gerando referências zombie em
        // slot[\playSynth] e impedindo o onFree de disparar.
        doneEnv = EnvGen.kr(
            Env([1, 1, 0], [(dur - 0.02).max(0.001), 0.02]),
            doneAction: 2
        );
        // Envelope de gate: release curto para stop suave sem clique.
        // Também libera o Synth (doneAction 2) — o primeiro dos dois
        // envelopes a atingir zero libera. Ambos são seguros.
        gateEnv = EnvGen.kr(Env.asr(0.01, 1, 0.03), gate, doneAction: 2);
        env = doneEnv * gateEnv;
        sig = PlayBuf.ar(2, bufnum, BufRateScale.kr(bufnum) * rate, loop: 0);
        panned = Balance2.ar(sig[0], sig[1], pan, amp * env);
        Out.ar(outFxBus,  panned * sendFx.lag(0.02));
        Out.ar(outRawBus, panned * sendRaw.lag(0.02));
    }).add;

    SynthDef(\loopVoice, { |bufnum, outFxBus, outRawBus, inBus = 0, rate = 1, amp = 1, pan = 0,
                           gate = 1, loopFrames = 44100, dubAmt = 0, feedback = 1,
                           sendFx = 1, sendRaw = 0|
        var env, phase, oldSig, newSig, mixed, dubLag, audioOut;
        env = EnvGen.kr(Env.asr(0.02, 1, 0.1), gate, doneAction: 2);
        phase = Phasor.ar(0, BufRateScale.kr(bufnum) * rate, 0, loopFrames);
        oldSig = BufRd.ar(2, bufnum, phase, loop: 1, interpolation: 2);
        newSig = SoundIn.ar([inBus, inBus + 1]);
        dubLag = Lag.kr(dubAmt, 0.05);
        mixed = (oldSig * feedback) + (newSig * dubLag);
        BufWr.ar(mixed, bufnum, phase);
        audioOut = Balance2.ar(oldSig[0], oldSig[1], pan, amp * env);
        Out.ar(outFxBus,  audioOut * sendFx.lag(0.02));
        Out.ar(outRawBus, audioOut * sendRaw.lag(0.02));
    }).add;

    // ---- EFEITOS — Fase 3 (com roteamento modular) ------------------
    //
    // Cada efeito agora tem TRÊS buses de saída/entrada:
    //   • inBus       — sinal principal (sourceBus por default, ou saída
    //                   de outro efeito para encadeamento)
    //   • micBus      — sinal do mic (incluído se includeMic = 1)
    //   • outBus      — saída individual deste efeito (sempre escrita)
    //   • masterBus   — fxBus geral (acumulador para o master). Escrita
    //                   condicional a sendToMaster.
    //
    // Roteamento de canais (chMode): afeta a leitura do micBus:
    //   0 = estéreo (default)    [mic1, mic2]
    //   1 = só CH1 (replicado)   [mic1, mic1]
    //   2 = só CH2 (replicado)   [mic2, mic2]
    //
    // Comportamento de retrocompatibilidade:
    //   includeMic=1, sendToMaster=1, chMode=0  → idêntico ao anterior.

    SynthDef(\fxTimeStretch, { |inBus, micBus, outBus, masterBus, buf,
                                mix = 1, bypass = 0, pan = 0,
                                includeMic = 1, sendToMaster = 1, chMode = 0,
                                stretch = 1, windowSize = 0.15, overlaps = 4|
        var ms, mic, input, inputMono, output, normPos, bufDur;
        ms = In.ar(micBus, 2);
        mic = [Select.ar(chMode, [ms[0], ms[0], ms[1]]),
               Select.ar(chMode, [ms[1], ms[0], ms[1]])];
        input = In.ar(inBus, 2) + (mic * includeMic.lag(0.05));
        inputMono = Mix.ar(input) * 0.5;
        bufDur = BufDur.kr(buf);
        BufWr.ar(inputMono, buf, Phasor.ar(0, BufRateScale.kr(buf), 0, BufFrames.kr(buf)));
        normPos = LFSaw.kr((bufDur * stretch.max(0.1)).reciprocal, 1).range(0, 1);
        output = Warp1.ar(1, buf, normPos, 1, windowSize, -1, overlaps, 0.05, 4) ! 2;
        output = output * mix * (1 - bypass.lag(0.05));
        output = Balance2.ar(output[0], output[1], pan.lag(0.02));
        Out.ar(outBus, output);
        Out.ar(masterBus, output * sendToMaster.lag(0.05));
    }).add;

    SynthDef(\fxReverse, { |inBus, micBus, outBus, masterBus, buf,
                            mix = 1, bypass = 0, pan = 0,
                            includeMic = 1, sendToMaster = 1, chMode = 0,
                            segmentDur = 1, density = 1|
        var ms, mic, input, output, writePos, trig, latchedPos, sweep, readPos, env;
        var trigRate;
        ms = In.ar(micBus, 2);
        mic = [Select.ar(chMode, [ms[0], ms[0], ms[1]]),
               Select.ar(chMode, [ms[1], ms[0], ms[1]])];
        input = In.ar(inBus, 2) + (mic * includeMic.lag(0.05));
        writePos = Phasor.ar(0, BufRateScale.kr(buf), 0, BufFrames.kr(buf));
        BufWr.ar(input, buf, writePos);
        trigRate = density.max(0.1) / segmentDur.max(0.1);
        trig = Impulse.ar(trigRate);
        latchedPos = Latch.ar(writePos, trig);
        sweep = Sweep.ar(trig, SampleRate.ir * BufRateScale.kr(buf));
        readPos = (latchedPos - sweep).wrap(0, BufFrames.kr(buf));
        output = BufRd.ar(2, buf, readPos, loop: 1, interpolation: 4);
        env = EnvGen.ar(
            Env([0, 1, 1, 0], [
                (segmentDur / density.max(0.1)) * 0.05,
                (segmentDur / density.max(0.1)) * 0.9,
                (segmentDur / density.max(0.1)) * 0.05
            ]),
            trig
        );
        output = output * env * mix * (1 - bypass.lag(0.05));
        output = output.sum.dup;
        output = Balance2.ar(output[0], output[1], pan.lag(0.02));
        Out.ar(outBus, output);
        Out.ar(masterBus, output * sendToMaster.lag(0.05));
    }).add;

    SynthDef(\fxADSR, { |inBus, micBus, outBus, masterBus,
                        mix = 1, bypass = 0, pan = 0,
                        includeMic = 1, sendToMaster = 1, chMode = 0,
                        gate = 0, atk = 0.01, dec = 0.1, sus = 0.7, rel = 0.5|
        var ms, mic, input, output, env;
        ms = In.ar(micBus, 2);
        mic = [Select.ar(chMode, [ms[0], ms[0], ms[1]]),
               Select.ar(chMode, [ms[1], ms[0], ms[1]])];
        input = In.ar(inBus, 2) + (mic * includeMic.lag(0.05));
        env = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, -4, 0), gate);
        output = input * env;
        output = output * mix * (1 - bypass.lag(0.05));
        output = output.sum.dup;
        output = Balance2.ar(output[0], output[1], pan.lag(0.02));
        Out.ar(outBus, output);
        Out.ar(masterBus, output * sendToMaster.lag(0.05));
    }).add;

    // ---- Modulation (RM / AM / FM) ---------------------------------
    // mode: 0=RM (ring), 1=AM (amplitude), 2=FM (delay-line modulated)
    // modFreq: Hz do oscilador modulator
    // depth: profundidade (0..1) — em RM atua só como mix interno;
    //                              em AM = índice de modulação clássico;
    //                              em FM = profundidade do delay variável
    // ratio: multiplicador da modFreq (extra fine-tuning ou intervalo)
    SynthDef(\fxModulation, { |inBus, micBus, outBus, masterBus,
                              mix = 1, bypass = 0, pan = 0,
                              includeMic = 1, sendToMaster = 1, chMode = 0,
                              mode = 0, modFreq = 200, depth = 0.5, ratio = 1.0|
        var ms, mic, input, modSig, effFreq, dLag;
        var rmOut, amOut, fmOut, output;

        ms = In.ar(micBus, 2);
        mic = [Select.ar(chMode, [ms[0], ms[0], ms[1]]),
               Select.ar(chMode, [ms[1], ms[0], ms[1]])];
        input = In.ar(inBus, 2) + (mic * includeMic.lag(0.05));

        effFreq = (modFreq.lag(0.05) * ratio.lag(0.05)).clip(0.01, 20000);
        modSig = SinOsc.ar(effFreq);
        dLag = depth.lag(0.05);

        // RM clássica: y = x * m  (sem DC, sidebands puras)
        rmOut = input * modSig;

        // AM clássica: y = x * (1 + d * m) * 0.5
        // o 0.5 compensa o DC ficando com ganho equivalente
        amOut = input * (1 + (dLag * modSig)) * 0.5;

        // FM via delay-line modulado: delay time varia com o oscilador
        // (vibrato em depth baixo, modulação de freq em depth alto)
        fmOut = DelayC.ar(input, 0.05,
            0.0025 + (dLag * 0.0025) + (modSig * dLag * 0.002));

        // Seleção do modo com pequeno lag para evitar clicks na troca
        output = Select.ar(mode.lag(0.01).round(1), [rmOut, amOut, fmOut]);

        output = output * mix * (1 - bypass.lag(0.05));
        output = Balance2.ar(output[0], output[1], pan.lag(0.02));
        Out.ar(outBus, output);
        Out.ar(masterBus, output * sendToMaster.lag(0.05));
    }).add;

    SynthDef(\fxFilter, { |inBus, micBus, outBus, masterBus,
                          mix = 1, bypass = 0, pan = 0,
                          includeMic = 1, sendToMaster = 1, chMode = 0,
                          lpfFreq = 20000, hpfFreq = 20, lpfRq = 1, hpfRq = 1,
                          lowGain = 0, midGain = 0, highGain = 0, midFreq = 1000|
        var ms, mic, input, output;
        ms = In.ar(micBus, 2);
        mic = [Select.ar(chMode, [ms[0], ms[0], ms[1]]),
               Select.ar(chMode, [ms[1], ms[0], ms[1]])];
        input = In.ar(inBus, 2) + (mic * includeMic.lag(0.05));
        output = RHPF.ar(input, hpfFreq.clip(20, 20000), hpfRq.clip(0.05, 2));
        output = RLPF.ar(output, lpfFreq.clip(20, 20000), lpfRq.clip(0.05, 2));
        output = BLowShelf.ar(output, 200, 1, lowGain.clip(-24, 24));
        output = BPeakEQ.ar(output, midFreq.clip(100, 10000), 1, midGain.clip(-24, 24));
        output = BHiShelf.ar(output, 5000, 1, highGain.clip(-24, 24));
        output = output * mix * (1 - bypass.lag(0.05));
        output = output.sum.dup;
        output = Balance2.ar(output[0], output[1], pan.lag(0.02));
        Out.ar(outBus, output);
        Out.ar(masterBus, output * sendToMaster.lag(0.05));
    }).add;

    SynthDef(\fxReverb, { |inBus, micBus, outBus, masterBus,
                          mix = 1, bypass = 0, pan = 0,
                          includeMic = 1, sendToMaster = 1, chMode = 0,
                          decay = 2, size = 1, damp = 0.5|
        var ms, mic, input, output;
        ms = In.ar(micBus, 2);
        mic = [Select.ar(chMode, [ms[0], ms[0], ms[1]]),
               Select.ar(chMode, [ms[1], ms[0], ms[1]])];
        input = In.ar(inBus, 2) + (mic * includeMic.lag(0.05));
        output = JPverb.ar(input,
            t60: decay.clip(0.1, 30),
            damp: damp.clip(0, 1),
            size: size.clip(0.5, 3),
            earlyDiff: 0.707, modDepth: 0.1, modFreq: 2);
        output = output * mix * (1 - bypass.lag(0.05));
        output = output.sum.dup;
        output = Balance2.ar(output[0], output[1], pan.lag(0.02));
        Out.ar(outBus, output);
        Out.ar(masterBus, output * sendToMaster.lag(0.05));
    }).add;

    SynthDef(\fxDelay, { |inBus, micBus, outBus, masterBus,
                         mix = 1, bypass = 0, pan = 0,
                         includeMic = 1, sendToMaster = 1, chMode = 0,
                         time = 0.5, feedback = 0.5|
        var ms, mic, input, output, dl, fbIn;
        ms = In.ar(micBus, 2);
        mic = [Select.ar(chMode, [ms[0], ms[0], ms[1]]),
               Select.ar(chMode, [ms[1], ms[0], ms[1]])];
        input = In.ar(inBus, 2) + (mic * includeMic.lag(0.05));
        fbIn = LocalIn.ar(2);
        dl = DelayN.ar(input + (fbIn * feedback.clip(0, 0.95)),
                       2.0, time.clip(0.001, 2).lag(0.05));
        LocalOut.ar(dl);
        output = dl * mix * (1 - bypass.lag(0.05));
        output = output.sum.dup;
        output = Balance2.ar(output[0], output[1], pan.lag(0.02));
        Out.ar(outBus, output);
        Out.ar(masterBus, output * sendToMaster.lag(0.05));
    }).add;

    SynthDef(\fxHarmonizer, { |inBus, micBus, outBus, masterBus,
                              mix = 1, bypass = 0, pan = 0,
                              includeMic = 1, sendToMaster = 1, chMode = 0,
                              voices = 4, spread = 2|
        var ms, mic, input, inputMono, output, voicesArr, gates;
        ms = In.ar(micBus, 2);
        mic = [Select.ar(chMode, [ms[0], ms[0], ms[1]]),
               Select.ar(chMode, [ms[1], ms[0], ms[1]])];
        input = In.ar(inBus, 2) + (mic * includeMic.lag(0.05));
        inputMono = Mix.ar(input) * 0.5;

        voicesArr = Array.fill(8, { |i|
            var modFreq = 0.25 + (i * 0.13);
            var pitch = LFNoise1.kr(modFreq) * spread;
            var voicePan = i.linlin(0, 7, -0.8, 0.8);
            var voice = PitchShift.ar(inputMono, 0.2, pitch.midiratio, 0.04, 0.01);
            Pan2.ar(voice, voicePan)
        });

        gates = Array.fill(8, { |i|
            (voices.max(0).min(8) - i).clip(0, 1).lag(0.08)
        });

        output = Mix(voicesArr * gates) / voices.max(1).sqrt;
        output = output * mix * (1 - bypass.lag(0.05));
        output = Balance2.ar(output[0], output[1], pan.lag(0.02));
        Out.ar(outBus, output);
        Out.ar(masterBus, output * sendToMaster.lag(0.05));
    }).add;
};
