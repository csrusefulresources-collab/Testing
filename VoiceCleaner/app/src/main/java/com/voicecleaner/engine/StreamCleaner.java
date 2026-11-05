package com.voicecleaner.engine;

/**
 * One-click studio voice chain (streaming, constant memory).
 *
 * hum notches -> rumble high-pass -> spectral denoise (decision directed Wiener, profile from
 * NoiseAnalyzer) -> late-reverb suppression -> residual gate -> body/presence/air EQ
 * -> de-esser -> compressor -> valve warmth -> slow level rider -> brick-wall limiter
 *
 * No AudioEffect.NoiseSuppressor is used: that API only works on a live microphone capture
 * session and cannot process a file.
 */
public final class StreamCleaner {

    private static final int N = 1024;
    private static final int HOP = 256;
    private static final int BINS = N / 2 + 1;

    private final int sr;
    private final Fft fft = new Fft(N);
    private final float[] win = new float[N];
    private final float[] norm = new float[HOP];
    private final float[] re = new float[N];
    private final float[] im = new float[N];
    private final float[] ob = new float[N];

    private final float[] gainPrev = new float[BINS];
    private final float[] gammaPrev = new float[BINS];
    private final float[] tailE = new float[BINS];
    private final float[] prof;
    private final float[] gSmooth = new float[BINS];

    private float[] carry = new float[N];
    private int carryLen = 0;
    private float[] pend = new float[0];

    private final Biquad hp1, hp2;
    private final Biquad[] hum;
    private final Biquad lowShelf, presence, highShelf;
    private final Dynamics.DeEsser deEsser;
    private final Dynamics.Compressor comp;
    private final Dynamics.Saturator sat;
    private final Dynamics.Limiter limiter;
    private final Dynamics.Gate gate;
    private final LevelRider rider;
    private final float tailDecay;

    public StreamCleaner(int sampleRate, float[] noiseProfile, float noiseFloorDb) {
        this.sr = sampleRate;
        for (int i = 0; i < N; i++) win[i] = (float) (0.5 - 0.5 * Math.cos(2 * Math.PI * i / N));
        for (int p = 0; p < HOP; p++) {
            float s = 0;
            for (int k = 0; p + k * HOP < N; k++) {
                float w = win[p + k * HOP];
                s += w * w;
            }
            norm[p] = s > 1e-6f ? s : 1f;
        }
        int bins = Math.min(BINS, noiseProfile != null ? noiseProfile.length : 0);
        prof = new float[BINS];
        for (int b = 0; b < BINS; b++) prof[b] = b < bins ? Math.max(noiseProfile[b], 1e-7f) : 1e-4f;
        java.util.Arrays.fill(gSmooth, 1f);

        hp1 = Biquad.highPass(sr, 72f, 0.707f);
        hp2 = Biquad.highPass(sr, 45f, 0.707f);
        float[] humF = {50f, 60f, 100f, 120f, 150f, 180f, 200f, 240f};
        hum = new Biquad[humF.length];
        for (int i = 0; i < humF.length; i++) hum[i] = Biquad.peaking(sr, humF[i], 40f, -24f);

        lowShelf = Biquad.lowShelf(sr, 190f, 3.0f);        // chest weight, "بھاری" voice
        presence = Biquad.peaking(sr, 3100f, 1.1f, 2.2f);  // clarity
        highShelf = Biquad.highShelf(sr, 9000f, -3.0f);    // tame hiss / harsh phone treble
        deEsser = new Dynamics.DeEsser(sr, -30f, 6f);
        comp = new Dynamics.Compressor(sr, -20f, 3.0f, 8f, 8f, 180f, 3.5f);
        sat = new Dynamics.Saturator(1.6f, 0.16f);
        limiter = new Dynamics.Limiter(sr, -1.0f);
        // Gate sits just above the file's own measured noise floor: between phrases the studio is
        // silent, but a soft breath or the tail of a word still passes.
        float gateTh = Math.min(-26f, Math.max(-46f, noiseFloorDb + 5f));
        gate = new Dynamics.Gate(sr, gateTh, -60f, 4f, 240f, 280f);
        rider = new LevelRider(gateTh + 6f);
        tailDecay = (float) Math.exp(-(double) HOP / (0.30 * sr));
    }

    public void process(float[] in, int off, int len, FloatList out) {
        if (pend.length < len) pend = new float[Math.max(len, pend.length * 2)];
        for (int i = 0; i < len; i++) {
            float x = in[off + i];
            for (int h = 0; h < hum.length; h++) x = hum[h].process(x);
            x = hp1.process(x);
            x = hp2.process(x);
            pend[i] = x;
        }

        int cn = carryLen;
        float[] full = new float[cn + len];
        System.arraycopy(carry, 0, full, 0, cn);
        System.arraycopy(pend, 0, full, cn, len);

        if (full.length < N) {
            carry = full;
            carryLen = full.length;
            return;
        }
        int frames = (full.length - N) / HOP + 1;
        int s = 0;
        for (int f = 0; f < frames; f++) {
            frame(full, s, out);
            s += HOP;
        }
        carryLen = full.length - s;
        if (carry.length < carryLen) carry = new float[Math.max(carryLen, N)];
        System.arraycopy(full, s, carry, 0, carryLen);
    }

    /** Emit the tail of the file. */
    public void flush(FloatList out) {
        float[] z = new float[N];
        for (int i = 0; i < 4; i++) process(z, 0, N, out);
        for (int i = 0; i < N; i++) {
            float v = finish(ob[i]);
            ob[i] = 0f;
            out.add(v);
        }
    }

    private void frame(float[] x, int start, FloatList out) {
        for (int i = 0; i < N; i++) {
            re[i] = x[start + i] * win[i];
            im[i] = 0f;
        }
        fft.forward(re, im);

        for (int b = 0; b < BINS; b++) {
            float rr = re[b], ii = im[b];
            float mag = (float) Math.sqrt(rr * rr + ii * ii);

            float noise = prof[b];
            float gamma = (mag * mag) / (noise * noise + 1e-12f);
            if (gamma > 1e6f) gamma = 1e6f;

            float xi = 0.97f * gainPrev[b] * gainPrev[b] * gammaPrev[b]
                    + 0.03f * Math.max(gamma - 1f, 0f);
            if (xi < 0f) xi = 0f;
            float g = xi / (1f + xi);
            if (g < 0.040f) g = 0.040f;                 // residual floor = natural, not gated

            float e = mag * mag;
            float rv = tailE[b];
            if (e < rv && rv > 1e-9f) {                 // late reverb tail is not direct sound
                float gr = (e - 0.62f * rv) / e;
                if (gr < 0.20f) gr = 0.20f;
                if (gr > 1f) gr = 1f;
                g *= gr;
            }
            tailE[b] = tailDecay * rv;

            gSmooth[b] = g;
            gammaPrev[b] = gamma;
            gainPrev[b] = g;
        }

        float prev = gSmooth[0];
        for (int b = 1; b < BINS - 1; b++) {
            float cur = gSmooth[b];
            gSmooth[b] = 0.25f * prev + 0.5f * cur + 0.25f * gSmooth[b + 1];
            prev = cur;
        }

        for (int b = 0; b < BINS; b++) {
            float g = gSmooth[b];
            re[b] *= g;
            im[b] *= g;
            if (b > 0 && b < N - b) {
                re[N - b] *= g;
                im[N - b] *= g;
            }
        }

        fft.inverse(re, im);

        for (int i = 0; i < N; i++) ob[i] += (re[i] * win[i]) / norm[i % HOP];
        for (int i = 0; i < HOP; i++) {
            float v = finish(ob[i]);
            out.add(v);
        }
        System.arraycopy(ob, HOP, ob, 0, N - HOP);
        for (int i = N - HOP; i < N; i++) ob[i] = 0f;
    }

    private float finish(float x) {
        x = gate.process(x);
        x = lowShelf.process(x);
        x = presence.process(x);
        x = highShelf.process(x);
        x = deEsser.process(x);
        x = comp.process(x);
        x = sat.process(x);
        x = rider.process(x, sr);
        x = limiter.process(x);
        if (x > 1f) x = 1f;
        if (x < -1f) x = -1f;
        return x;
    }

    /**
     * Slow level rider. It locks a gain while the reciter is speaking and FREEZES that gain
     * through the pauses, so every phrase gets the same boost and the pauses never get pumped up.
     */
    private static final class LevelRider {
        private float gain = 1f, env = 0f, coefEnv = 0f, coefMove = 0f;
        private final float speechLin;
        private static final float TARGET = 0.145f;      // ~ -16.8 dBFS RMS
        private static final float MIN_G = 0.40f, MAX_G = 9.0f;   // max +19 dB

        LevelRider(float speechThreshDb) {
            this.speechLin = (float) Math.pow(10, speechThreshDb / 20.0);
        }

        float process(float x, int sr) {
            if (coefEnv == 0f) {
                coefEnv = (float) Math.exp(-1.0 / (0.040 * sr));
                coefMove = (float) Math.exp(-1.0 / (0.300 * sr));
            }
            env = coefEnv * env + (1 - coefEnv) * x * x;
            if (env < speechLin * speechLin) {
                return x * gain;                        // pause: hold the gain, do not lift noise
            }
            float rms = (float) Math.sqrt(env);
            float want = TARGET / rms;
            if (want < MIN_G) want = MIN_G;
            if (want > MAX_G) want = MAX_G;
            gain = coefMove * gain + (1 - coefMove) * want;
            return x * gain;
        }
    }
}
