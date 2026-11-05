package com.voicecleaner.engine;

/** Tiny growable float buffer (avoids ArrayList<Float> boxing on old devices). */
public final class FloatList {
    private float[] a;
    private int n = 0;

    public FloatList() { this(8192); }

    public FloatList(int cap) { a = new float[Math.max(16, cap)]; }

    public void add(float v) {
        if (n == a.length) {
            float[] b = new float[a.length * 2];
            System.arraycopy(a, 0, b, 0, n);
            a = b;
        }
        a[n++] = v;
    }

    public void addAll(float[] src, int off, int len) {
        ensure(n + len);
        System.arraycopy(src, off, a, n, len);
        n += len;
    }

    public void addAll(FloatList o) {
        ensure(n + o.n);
        System.arraycopy(o.a, 0, a, n, o.n);
        n += o.n;
    }

    private void ensure(int cap) {
        if (cap > a.length) {
            int size = a.length;
            while (size < cap) size *= 2;
            float[] b = new float[size];
            System.arraycopy(a, 0, b, 0, n);
            a = b;
        }
    }

    public int size() { return n; }

    public float get(int i) { return a[i]; }

    public float[] raw() { return a; }

    public void clear() { n = 0; }

    public float[] toArray() {
        float[] r = new float[n];
        System.arraycopy(a, 0, r, 0, n);
        return r;
    }
}
