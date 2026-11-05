package com.voicecleaner.engine;

/** Minimal in-place iterative radix-2 FFT (no dependencies, works on any Android version). */
public final class Fft {
    private final int n;
    private final int[] rev;
    private final float[] cosT;
    private final float[] sinT;

    public Fft(int n) {
        if (Integer.bitCount(n) != 1) throw new IllegalArgumentException("size must be power of 2");
        this.n = n;
        this.rev = new int[n];
        int bits = Integer.numberOfTrailingZeros(n);
        for (int i = 0; i < n; i++) rev[i] = Integer.reverse(i) >>> (32 - bits);
        int half = n / 2;
        cosT = new float[half];
        sinT = new float[half];
        for (int i = 0; i < half; i++) {
            double a = -2.0 * Math.PI * i / n;
            cosT[i] = (float) Math.cos(a);
            sinT[i] = (float) Math.sin(a);
        }
    }

    public void forward(float[] re, float[] im) { transform(re, im, false); }

    public void inverse(float[] re, float[] im) { transform(re, im, true); }

    private void transform(float[] re, float[] im, boolean inv) {
        for (int i = 0; i < n; i++) {
            int j = rev[i];
            if (j > i) {
                float t = re[i]; re[i] = re[j]; re[j] = t;
                t = im[i]; im[i] = im[j]; im[j] = t;
            }
        }
        for (int len = 2; len <= n; len <<= 1) {
            int half = len >> 1;
            int step = n / len;
            for (int i = 0; i < n; i += len) {
                int k = 0;
                for (int j = 0; j < half; j++) {
                    float c = cosT[k];
                    float s = inv ? -sinT[k] : sinT[k];
                    int a = i + j;
                    int b = a + half;
                    float xr = re[b] * c - im[b] * s;
                    float xi = re[b] * s + im[b] * c;
                    re[b] = re[a] - xr;
                    im[b] = im[a] - xi;
                    re[a] += xr;
                    im[a] += xi;
                    k += step;
                }
            }
        }
        if (inv) {
            float inv_n = 1f / n;
            for (int i = 0; i < n; i++) { re[i] *= inv_n; im[i] *= inv_n; }
        }
    }
}
