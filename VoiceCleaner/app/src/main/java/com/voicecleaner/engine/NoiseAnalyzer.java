package com.voicecleaner.engine;

/**
 * Pass 1: learns the room/device noise fingerprint of the whole file before any processing.
 *
 * Per frequency bin we keep the 8 smallest frame magnitudes (a light minimum-statistics
 * histogram) and the running mean. The estimate is the average of the lowest four, capped at a
 * fraction of the mean, so a bin where the reciter's voice is always present (his fundamental,
 * for example) is never mistaken for noise and stripped away.
 */
public final class NoiseAnalyzer {

    private static final int N = 1024;
    private static final int HOP = 256;
    private static final int BINS = N / 2 + 1;
    private static final int KEEP = 8;

    private final Fft fft = new Fft(N);
    private final float[] win = new float[N];
    private final float[] re = new float[N];
    private final float[] im = new float[N];
    private final float[] mins = new float[BINS * KEEP];
    private final float[] mean = new float[BINS];
    private final float[] carry = new float[N];
    private int carryLen = 0;
    private double energy = 0;
    private long count = 0;

    // time-domain noise floor: the 6 quietest 20 ms blocks of the whole file
    private static final int RMS_CAP = 4096;
    private final float[] rmsHist = new float[RMS_CAP];
    private final float[] blk = new float[882];
    private int blkLen = 0;
    private int rmsN = 0;

    public NoiseAnalyzer() {
        for (int i = 0; i < N; i++) win[i] = (float) (0.5 - 0.5 * Math.cos(2 * Math.PI * i / N));
        java.util.Arrays.fill(mins, Float.MAX_VALUE);
    }

    public void accept(float[] pcm, int len) {
        for (int i = 0; i < len; i++) {
            blk[blkLen++] = pcm[i];
            if (blkLen == blk.length) { trackRms(); blkLen = 0; }
        }
        float[] full = new float[carryLen + len];
        System.arraycopy(carry, 0, full, 0, carryLen);
        System.arraycopy(pcm, 0, full, carryLen, len);

        if (full.length < N) {
            System.arraycopy(full, 0, carry, 0, full.length);
            carryLen = full.length;
            return;
        }
        int s = 0;
        while (s + N <= full.length) {
            analyzeAt(full, s);
            s += HOP;
        }
        carryLen = full.length - s;
        System.arraycopy(full, s, carry, 0, carryLen);
    }

    private void analyzeAt(float[] x, int start) {
        for (int i = 0; i < N; i++) {
            re[i] = x[start + i] * win[i];
            im[i] = 0f;
        }
        fft.forward(re, im);
        for (int b = 0; b < BINS; b++) {
            float rr = re[b], ii = im[b];
            float mag = (float) Math.sqrt(rr * rr + ii * ii);
            insort(b, mag);
            mean[b] += (mag - mean[b]) * 0.02f;
            energy += mag * mag;
        }
        count++;
    }

    private void trackRms() {
        if (rmsN >= rmsHist.length) return;
        double s = 0;
        for (int i = 0; i < blk.length; i++) s += (double) blk[i] * blk[i];
        rmsHist[rmsN++] = (float) Math.sqrt(s / blk.length);
    }

    private void insort(int b, float v) {
        int base = b * KEEP;
        if (v >= mins[base + KEEP - 1]) return;
        int i = KEEP - 1;
        while (i > 0 && mins[base + i - 1] > v) {
            mins[base + i] = mins[base + i - 1];
            i--;
        }
        mins[base + i] = v;
    }

    /** Quietest measured stretch of the file, in dBFS. Used to set the gate threshold. */
    public float noiseFloorDb() {
        if (rmsN == 0) return -60f;
        int n = Math.min(rmsN, rmsHist.length);
        float[] t = new float[n];
        System.arraycopy(rmsHist, 0, t, 0, n);
        java.util.Arrays.sort(t);
        // 20th percentile: ignores the few near-zero blocks that a strict minimum would latch onto
        float v = t[Math.max(0, (int) (n * 0.20))];
        if (v < 1e-9f) v = 1e-9f;
        return (float) (20.0 * Math.log10(v));
    }

    /** @return per-bin noise magnitude estimate (same windowed scale the cleaner uses). */
    public float[] finish() {
        float avg = (float) Math.sqrt(energy / Math.max(1, count * BINS));
        float hardFloor = Math.max(avg * 0.0004f, 1e-6f);
        float[] prof = new float[BINS];
        for (int b = 0; b < BINS; b++) {
            int base = b * KEEP;
            float sum = 0f;
            int c = 0;
            for (int k = 0; k < 4; k++) {
                float v = mins[base + k];
                if (v < Float.MAX_VALUE) { sum += v; c++; }
            }
            float p = c > 0 ? sum / c : hardFloor;
            // min-statistics under-reads broadband noise, so scale up; the overshoot is what
            // actually removes fan / traffic / hiss instead of merely softening it.
            p *= 2.6f;
            float cap = mean[b] * 0.85f;                   // never eat a bin the voice owns
            if (cap > hardFloor && p > cap) p = cap;
            prof[b] = Math.max(p, hardFloor);
        }
        return prof;
    }
}
