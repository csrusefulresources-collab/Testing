package com.voicecleaner.engine;

import java.io.IOException;
import java.io.OutputStream;

import de.sciss.jump3r.mp3.Lame;
import de.sciss.jump3r.mp3.LameGlobalFlags;
import de.sciss.jump3r.mp3.MPEGMode;
import de.sciss.jump3r.mp3.VbrMode;

/**
 * MP3 encoder using the pure-Java LAME port (jump3r). No native code, no NDK,
 * so it works on every ABI and every Android version from 5.0 up.
 */
public final class Mp3Encoder {

    /** LAME's 32-bit API expects samples scaled to +/- 2^23 (24-bit full scale). */
    private static final float INT_SCALE = (float) (1 << 23);

    private final Lame lame = new Lame();
    private final LameGlobalFlags gfp;
    private final byte[] mp3buf = new byte[16384];
    private final int[] left;
    private final int[] right;

    public Mp3Encoder(int sampleRate, int bitrateKbps) {
        left = new int[4096];
        right = new int[4096];
        gfp = lame.lame_init();
        gfp.num_channels = 1;
        gfp.in_samplerate = sampleRate;
        gfp.mode = MPEGMode.MONO;
        gfp.VBR = VbrMode.vbr_off;
        gfp.brate = bitrateKbps;
        gfp.quality = 3;
        gfp.bWriteVbrTag = false;
        int rc = lame.lame_init_params(gfp);
        if (rc < 0) throw new IllegalStateException("LAME init failed: " + rc);
    }

    public void write(float[] mono, int off, int len, OutputStream os) throws IOException {
        int i = 0;
        while (i < len) {
            int n = Math.min(left.length, len - i);
            for (int k = 0; k < n; k++) {
                float v = mono[off + i + k];
                if (v > 1f) v = 1f;
                if (v < -1f) v = -1f;
                int s = (int) (v * INT_SCALE);
                left[k] = s;
                right[k] = s;
            }
            int got = lame.lame_encode_buffer_int(gfp, left, right, n, mp3buf, 0, mp3buf.length);
            if (got > 0) os.write(mp3buf, 0, got);
            i += n;
        }
    }

    public void finish(OutputStream os) throws IOException {
        int got = lame.lame_encode_flush(gfp, mp3buf, 0, mp3buf.length);
        if (got > 0) os.write(mp3buf, 0, got);
        os.flush();
        lame.lame_close(gfp);
    }
}
