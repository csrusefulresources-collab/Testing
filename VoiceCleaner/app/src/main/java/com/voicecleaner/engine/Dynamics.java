package com.voicecleaner.engine;

/** Gate, compressor, de-esser, saturator and look-ahead limiter. All sample-rate aware, streaming. */
public final class Dynamics {

    private Dynamics() { }

    /** Smooth downward expander: removes residual noise floor between phrases. */
    public static final class Gate {
        private final float threshLin, floorGain;
        private final float relCoef, attCoef;
        private final int holdSamples;
        private final float detCoef;
        private float envSq = 0f, gain = 1f;
        private int hold = 0;

        public Gate(float sr, float threshDb, float floorDb, float attackMs, float releaseMs, float holdMs) {
            this.threshLin = (float) Math.pow(10, threshDb / 20.0);
            this.floorGain = (float) Math.pow(10, floorDb / 20.0);
            this.attCoef = (float) Math.exp(-1.0 / (0.001 * attackMs * sr));
            this.relCoef = (float) Math.exp(-1.0 / (0.001 * releaseMs * sr));
            this.holdSamples = Math.max(1, (int) (0.001f * holdMs * sr));
            this.detCoef = (float) Math.exp(-1.0 / (0.012 * sr));   // 12 ms RMS detector
        }

        public float process(float x) {
            // RMS detector, not peak: broadband noise sits below the threshold even at its peaks,
            // so a phrase gap actually becomes silent instead of flickering open.
            envSq = detCoef * envSq + (1 - detCoef) * x * x;
            float rms = (float) Math.sqrt(envSq);
            float target;
            if (rms > threshLin) { hold = holdSamples; target = 1f; }
            else if (hold > 0) { hold--; target = 1f; }
            else target = floorGain;
            float c = target > gain ? attCoef : relCoef;
            gain = c * gain + (1 - c) * target;
            return x * gain;
        }
    }

    /** Gentle broadcast-style compressor with soft knee. */
    public static final class Compressor {
        private final float threshDb, ratio, kneeDb, makeupLin;
        private final float attCoef, relCoef;
        private float env = 0f;
        private float gainDb = 0f;

        public Compressor(float sr, float threshDb, float ratio, float kneeDb,
                          float attackMs, float releaseMs, float makeupDb) {
            this.threshDb = threshDb;
            this.ratio = ratio;
            this.kneeDb = kneeDb;
            this.makeupLin = (float) Math.pow(10, makeupDb / 20.0);
            this.attCoef = (float) Math.exp(-1.0 / (0.001 * attackMs * sr));
            this.relCoef = (float) Math.exp(-1.0 / (0.001 * releaseMs * sr));
        }

        public float process(float x) {
            float a = Math.abs(x);
            if (a > env) env = attCoef * env + (1 - attCoef) * a;
            else env = relCoef * env + (1 - relCoef) * a;
            float db = 20f * (float) Math.log10(env + 1e-9f);
            float over = db - threshDb;
            float want = 0f;
            if (over > kneeDb / 2) want = -(over - over / ratio);
            else if (over > -kneeDb / 2) {
                float t = over + kneeDb / 2;
                want = -(t * t / (2 * kneeDb)) * (1 - 1 / ratio);
            }
            float c = want < gainDb ? attCoef : relCoef;
            gainDb = c * gainDb + (1 - c) * want;
            return x * (float) Math.pow(10, gainDb / 20.0) * makeupLin;
        }
    }

    /** Side-chained high-band tamer: keeps "س" and "ش" from spitting. */
    public static final class DeEsser {
        private final Biquad hp, lp;
        private final float threshLin, relCoef, attCoef;
        private float env = 0f, gain = 1f, maxReduction;

        public DeEsser(float sr, float threshDb, float maxReductionDb) {
            hp = Biquad.highPass(sr, 5000f, 0.7f);
            lp = Biquad.lowPass(sr, 8500f, 0.7f);
            this.threshLin = (float) Math.pow(10, threshDb / 20.0);
            this.maxReduction = (float) Math.pow(10, -maxReductionDb / 20.0);
            this.attCoef = (float) Math.exp(-1.0 / (0.001 * 2.0 * sr));
            this.relCoef = (float) Math.exp(-1.0 / (0.001 * 90.0 * sr));
        }

        public float process(float x) {
            float band = lp.process(hp.process(x));
            float a = Math.abs(band);
            env = a > env ? attCoef * env + (1 - attCoef) * a : relCoef * env + (1 - relCoef) * a;
            float target = 1f;
            if (env > threshLin) {
                float over = env / threshLin;
                target = Math.max(maxReduction, 1f / (1f + (over - 1f) * 0.5f));
            }
            float c = target < gain ? attCoef : relCoef;
            gain = c * gain + (1 - c) * target;
            return x * gain;
        }
    }

    /** Very mild valve-style soft saturation: adds harmonic weight ("دم") without audible distortion. */
    public static final class Saturator {
        private final float drive, norm, mix;
        public Saturator(float drive, float mix) {
            this.drive = drive;
            this.norm = (float) (1.0 / Math.tanh(drive));
            this.mix = mix;
        }
        public float process(float x) {
            float s = (float) Math.tanh(drive * x) * norm;
            return x * (1 - mix) + s * mix;
        }
    }

    /** Look-ahead brick-wall limiter, guaranteed ceiling. */
    public static final class Limiter {
        private final float ceiling, relCoef;
        private final float[] delay;
        private int idx = 0;
        private float env = 0f, gain = 1f;

        public Limiter(float sr, float ceilingDb) {
            this.ceiling = (float) Math.pow(10, ceilingDb / 20.0);
            this.relCoef = (float) Math.exp(-1.0 / (0.001 * 60.0 * sr));
            int look = Math.max(1, (int) (0.004f * sr));
            delay = new float[look];
        }

        public float process(float x) {
            float a = Math.abs(x);
            env = a > env ? a : relCoef * env + (1 - relCoef) * a;
            float target = env > ceiling ? ceiling / env : 1f;
            // instant attack (look-ahead delay covers it), smooth release
            if (target < gain) gain = target;
            else gain = relCoef * gain + (1 - relCoef) * target;
            float out = delay[idx] * gain;
            delay[idx] = x;
            idx = (idx + 1) % delay.length;
            if (out > ceiling) out = ceiling;
            if (out < -ceiling) out = -ceiling;
            return out;
        }
    }
}
