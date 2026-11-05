package com.voicecleaner.engine;

/** Cookbook biquad (RBJ) with double-precision state, transposed direct form II. */
public final class Biquad {
    private float b0, b1, b2, a1, a2;
    private double z1, z2;

    private void set(float nb0, float nb1, float nb2, float na0, float na1, float na2) {
        b0 = nb0 / na0; b1 = nb1 / na0; b2 = nb2 / na0;
        a1 = na1 / na0; a2 = na2 / na0;
    }

    public void reset() { z1 = 0; z2 = 0; }

    public float process(float x) {
        double y = b0 * x + z1;
        z1 = b1 * x - a1 * y + z2;
        z2 = b2 * x - a2 * y;
        return (float) y;
    }

    public static Biquad highPass(float sr, float f, float q) {
        double w = 2 * Math.PI * f / sr, cw = Math.cos(w), sw = Math.sin(w), al = sw / (2 * q);
        Biquad b = new Biquad();
        b.set((float) ((1 + cw) / 2), (float) (-(1 + cw)), (float) ((1 + cw) / 2),
                (float) (1 + al), (float) (-2 * cw), (float) (1 - al));
        return b;
    }

    public static Biquad lowPass(float sr, float f, float q) {
        double w = 2 * Math.PI * f / sr, cw = Math.cos(w), sw = Math.sin(w), al = sw / (2 * q);
        Biquad b = new Biquad();
        b.set((float) ((1 - cw) / 2), (float) (1 - cw), (float) ((1 - cw) / 2),
                (float) (1 + al), (float) (-2 * cw), (float) (1 - al));
        return b;
    }

    public static Biquad peaking(float sr, float f, float q, float gainDb) {
        double A = Math.pow(10, gainDb / 40.0);
        double w = 2 * Math.PI * f / sr, cw = Math.cos(w), sw = Math.sin(w), al = sw / (2 * q);
        Biquad b = new Biquad();
        b.set((float) (1 + al * A), (float) (-2 * cw), (float) (1 - al * A),
                (float) (1 + al / A), (float) (-2 * cw), (float) (1 - al / A));
        return b;
    }

    public static Biquad lowShelf(float sr, float f, float gainDb) {
        double A = Math.pow(10, gainDb / 40.0);
        double w = 2 * Math.PI * f / sr, cw = Math.cos(w), sw = Math.sin(w);
        double al = sw / 2 * Math.sqrt(2.0), k = 2 * Math.sqrt(A) * al;
        Biquad b = new Biquad();
        b.set((float) (A * ((A + 1) - (A - 1) * cw + k)),
                (float) (2 * A * ((A - 1) - (A + 1) * cw)),
                (float) (A * ((A + 1) - (A - 1) * cw - k)),
                (float) ((A + 1) + (A - 1) * cw + k),
                (float) (-2 * ((A - 1) + (A + 1) * cw)),
                (float) ((A + 1) + (A - 1) * cw - k));
        return b;
    }

    public static Biquad highShelf(float sr, float f, float gainDb) {
        double A = Math.pow(10, gainDb / 40.0);
        double w = 2 * Math.PI * f / sr, cw = Math.cos(w), sw = Math.sin(w);
        double al = sw / 2 * Math.sqrt(2.0), k = 2 * Math.sqrt(A) * al;
        Biquad b = new Biquad();
        b.set((float) (A * ((A + 1) + (A - 1) * cw + k)),
                (float) (-2 * A * ((A - 1) + (A + 1) * cw)),
                (float) (A * ((A + 1) + (A - 1) * cw - k)),
                (float) ((A + 1) - (A - 1) * cw + k),
                (float) (2 * ((A - 1) - (A + 1) * cw)),
                (float) ((A + 1) - (A - 1) * cw - k));
        return b;
    }

    public static Biquad bandPass(float sr, float f, float q) {
        double w = 2 * Math.PI * f / sr, cw = Math.cos(w), sw = Math.sin(w), al = sw / (2 * q);
        Biquad b = new Biquad();
        b.set((float) al, 0f, (float) -al, (float) (1 + al), (float) (-2 * cw), (float) (1 - al));
        return b;
    }
}
