package com.voicecleaner.app;

import android.content.Context;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.net.Uri;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * Decodes any Android-supported audio file to mono float PCM at a fixed rate, streaming:
 * constant memory, so a 5 second clip and a 90 minute bayan both work.
 * Two short passes over the file are used (analyse noise, then clean), never a full in-memory copy.
 */
final class Decoder {

    interface Sink {
        void accept(float[] buf, int len) throws Exception;
    }

    private Decoder() { }

    static void decode(Context ctx, Uri uri, int targetSr, Sink sink) throws IOException {
        MediaExtractor ex = new MediaExtractor();
        int track = -1;
        MediaFormat fmt = null;
        try {
            ex.setDataSource(ctx, uri, null);
            for (int i = 0; i < ex.getTrackCount(); i++) {
                MediaFormat f = ex.getTrackFormat(i);
                String mime = f.getString(MediaFormat.KEY_MIME);
                if (mime != null && mime.startsWith("audio/")) {
                    track = i;
                    fmt = f;
                    break;
                }
            }
            if (track < 0 || fmt == null) throw new IOException("no-audio-track");
            ex.selectTrack(track);

            int srcSr = fmt.containsKey(MediaFormat.KEY_SAMPLE_RATE)
                    ? fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE) : targetSr;
            if (srcSr <= 0) srcSr = targetSr;

            MediaCodec codec = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME));
            codec.configure(fmt, null, null, 0);
            codec.start();

            LinearResampler rs = new LinearResampler(srcSr, targetSr);
            float[] mono = new float[8192];
            float[] outBuf = new float[8192];
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean inputDone = false;
            boolean outputDone = false;
            boolean floatPcm = false;

            while (!outputDone) {
                if (!inputDone) {
                    int inIdx = codec.dequeueInputBuffer(10000);
                    if (inIdx >= 0) {
                        ByteBuffer ib = codec.getInputBuffer(inIdx);
                        int sz = ib == null ? -1 : ex.readSampleData(ib, 0);
                        if (sz < 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputDone = true;
                        } else {
                            codec.queueInputBuffer(inIdx, 0, sz, ex.getSampleTime(), 0);
                            ex.advance();
                        }
                    }
                }

                int outIdx = codec.dequeueOutputBuffer(info, 10000);
                if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    MediaFormat of = codec.getOutputFormat();
                    if (of.containsKey("pcm-encoding")) {
                        floatPcm = of.getInteger("pcm-encoding") == 4; // ENCODING_PCM_FLOAT
                    }
                    continue;
                }
                if (outIdx < 0) continue;

                ByteBuffer ob = codec.getOutputBuffer(outIdx);
                if (ob != null && info.size > 0) {
                    ob.position(info.offset);
                    ob.limit(info.offset + info.size);
                    ob.order(ByteOrder.nativeOrder());

                    int ch = 1;
                    if (codec.getOutputFormat().containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                        ch = Math.max(1, codec.getOutputFormat().getInteger(MediaFormat.KEY_CHANNEL_COUNT));
                    }

                    int frames;
                    if (floatPcm) {
                        int avail = ob.remaining() / 4;
                        frames = avail / ch;
                        if (frames > mono.length) mono = new float[frames];
                        for (int f = 0; f < frames; f++) {
                            float sum = 0;
                            for (int c = 0; c < ch; c++) sum += ob.getFloat();
                            mono[f] = sum / ch;
                        }
                    } else {
                        int avail = ob.remaining() / 2;
                        frames = avail / ch;
                        if (frames > mono.length) mono = new float[frames];
                        for (int f = 0; f < frames; f++) {
                            int sum = 0;
                            for (int c = 0; c < ch; c++) sum += ob.getShort();
                            mono[f] = (sum / (float) ch) / 32768f;
                        }
                    }

                    int n = rs.process(mono, frames, outBuf);
                    if (n > 0) {
                        try {
                            sink.accept(outBuf, n);
                        } catch (IOException e) {
                            throw e;
                        } catch (Exception e) {
                            throw new IOException(e);
                        }
                    }
                }

                codec.releaseOutputBuffer(outIdx, false);
                if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputDone = true;
            }

            int n = rs.flush(outBuf);
            if (n > 0) {
                try {
                    sink.accept(outBuf, n);
                } catch (Exception e) {
                    throw new IOException(e);
                }
            }

            try { codec.stop(); } catch (Exception ignored) { }
            codec.release();
        } finally {
            try { ex.release(); } catch (Exception ignored) { }
        }
    }

    /** Simple linear resampler with carried state between blocks. */
    static final class LinearResampler {
        private final double step;
        private double pos = 0;
        private float last = 0f;
        private boolean hasLast = false;

        LinearResampler(int src, int dst) {
            this.step = (double) src / (double) dst;
        }

        int process(float[] in, int frames, float[] out) {
            if (frames <= 0) return 0;
            int w = 0;
            int cap = out.length;
            for (int i = 0; i < frames; i++) {
                if (!hasLast) { last = in[i]; hasLast = true; pos = 0; continue; }
                while (pos < 1.0) {
                    float v = last + (in[i] - last) * (float) pos;
                    if (w < cap) out[w++] = v;
                    pos += step;
                }
                pos -= 1.0;
                last = in[i];
            }
            return w;
        }

        int flush(float[] out) { return 0; }
    }
}
