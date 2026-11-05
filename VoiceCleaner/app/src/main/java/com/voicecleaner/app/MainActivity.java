package com.voicecleaner.app;

import android.Manifest;
import android.app.Activity;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.media.MediaScannerConnection;
import android.media.MediaPlayer;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

import com.voicecleaner.engine.FloatList;
import com.voicecleaner.engine.Mp3Encoder;
import com.voicecleaner.engine.NoiseAnalyzer;
import com.voicecleaner.engine.StreamCleaner;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class MainActivity extends Activity {

    private static final int REQ_PICK = 1001;
    private static final int REQ_WRITE = 1002;
    private static final int TARGET_SR = 44100;
    private static final int MP3_KBPS = 192;

    private Button btnPick, btnClean, btnSave, btnPlayBefore, btnPlayAfter, btnStop;
    private TextView status;

    private Uri picked;
    private File cleanedFile;
    private MediaPlayer player;
    private volatile boolean busy = false;
    private String lastSaved = null;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setContentView(R.layout.activity_main);

        status = (TextView) findViewById(R.id.status);
        btnPick = (Button) findViewById(R.id.btnPick);
        btnClean = (Button) findViewById(R.id.btnClean);
        btnSave = (Button) findViewById(R.id.btnSave);
        btnPlayBefore = (Button) findViewById(R.id.btnPlayBefore);
        btnPlayAfter = (Button) findViewById(R.id.btnPlayAfter);
        btnStop = (Button) findViewById(R.id.btnStop);

        btnPick.setOnClickListener(v -> pickAudio());
        btnClean.setOnClickListener(v -> startClean());
        btnSave.setOnClickListener(v -> saveAudio());
        btnPlayBefore.setOnClickListener(v -> play(true));
        btnPlayAfter.setOnClickListener(v -> play(false));
        btnStop.setOnClickListener(v -> stopPlayer(true));

        for (Button bt : new Button[]{btnPick, btnClean, btnSave, btnPlayBefore, btnPlayAfter, btnStop}) {
            bt.setAllCaps(false);
        }

        setStatus("خوش آمدید۔ پہلے آڈیو منتخب کریں، پھر آڈیو صاف کریں، پھر محفوظ کریں۔");
    }

    // ------------------------------------------------------------------ pick
    private void pickAudio() {
        if (busy) return;
        stopPlayer(false);
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("audio/*");
        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            startActivityForResult(i, REQ_PICK);
        } catch (Exception e) {
            setStatus("اس موبائل پر فائل چننے کی اسکرین نہیں کھل سکی۔ دوبارہ کوشش کریں۔");
        }
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req != REQ_PICK) return;
        if (res != RESULT_OK || data == null || data.getData() == null) {
            setStatus("کوئی آڈیو منتخب نہیں ہوئی۔");
            return;
        }
        picked = data.getData();
        try {
            getContentResolver().takePersistableUriPermission(picked,
                    data.getFlags() & Intent.FLAG_GRANT_READ_URI_PERMISSION);
        } catch (Exception ignored) { }

        cleanedFile = null;
        lastSaved = null;
        btnClean.setEnabled(true);
        btnSave.setEnabled(false);
        btnPlayBefore.setVisibility(View.GONE);
        btnPlayAfter.setVisibility(View.GONE);
        btnStop.setVisibility(View.GONE);

        String name = displayName(picked);
        setStatus("آڈیو منتخب ہو گئی: " + name + "\nاب آڈیو صاف کریں کا بٹن دبائیں۔");
        btnClean.requestFocus();
        btnClean.announceForAccessibility("آڈیو منتخب ہو گئی۔ اب آڈیو صاف کریں کا بٹن دبائیں۔");
    }

    private String displayName(Uri uri) {
        String name = "آڈیو فائل";
        try (Cursor c = getContentResolver().query(uri, null, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                int idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (idx >= 0 && c.getString(idx) != null) name = c.getString(idx);
            }
        } catch (Exception ignored) { }
        return name;
    }

    // ------------------------------------------------------------------ clean
    private void startClean() {
        if (picked == null || busy) return;
        busy = true;
        stopPlayer(false);
        btnPick.setEnabled(false);
        btnClean.setEnabled(false);
        btnSave.setEnabled(false);
        btnPlayBefore.setVisibility(View.GONE);
        btnPlayAfter.setVisibility(View.GONE);

        setStatus("آڈیو صاف ہو رہی ہے۔ پہلے کمرے کا شور سیکھا جا رہا ہے، پھر آواز بنائی جا رہی ہے۔ براہ کرم انتظار کریں۔");

        final Uri src = picked;
        new Thread(() -> {
            try {
                long t0 = System.currentTimeMillis();

                final NoiseAnalyzer analyzer = new NoiseAnalyzer();
                Decoder.decode(MainActivity.this, src, TARGET_SR, analyzer::accept);
                final float[] profile = analyzer.finish();
                final float floorDb = analyzer.noiseFloorDb();

                runOnUiThread(() -> setStatus("شور کی پہچان مکمل۔ اب آواز صاف اور طاقتور بنائی جا رہی ہے۔"));

                File out = new File(getCacheDir(), "voicecleaner_clean.mp3");
                if (out.exists() && !out.delete()) throw new Exception("cache write failed");

                FileOutputStream fos = new FileOutputStream(out);
                Mp3Encoder enc = new Mp3Encoder(TARGET_SR, MP3_KBPS);
                final StreamCleaner cleaner = new StreamCleaner(TARGET_SR, profile, floorDb);
                final FloatList buf = new FloatList(1 << 15);
                try {
                    Decoder.decode(MainActivity.this, src, TARGET_SR, (pcm, len) -> {
                        cleaner.process(pcm, 0, len, buf);
                        if (buf.size() >= 32768) {
                            enc.write(buf.raw(), 0, buf.size(), fos);
                            buf.clear();
                        }
                    });
                    cleaner.flush(buf);
                    if (buf.size() > 0) enc.write(buf.raw(), 0, buf.size(), fos);
                    enc.finish(fos);
                } finally {
                    try { fos.close(); } catch (Exception ignored) { }
                }

                long secs = Math.max(1, (System.currentTimeMillis() - t0) / 1000);
                final long sizeKb = Math.max(1, out.length() / 1024);
                if (out.length() < 2000) throw new Exception("صاف شدہ فائل بن نہیں سکی");

                runOnUiThread(() -> {
                    busy = false;
                    cleanedFile = out;
                    btnPick.setEnabled(true);
                    btnClean.setEnabled(true);
                    btnSave.setEnabled(true);
                    btnPlayBefore.setVisibility(View.VISIBLE);
                    btnPlayAfter.setVisibility(View.VISIBLE);
                    btnStop.setVisibility(View.VISIBLE);
                    setStatus("آڈیو صاف ہو گئی۔ وقت: " + secs + " سیکنڈ۔ سائز: " + sizeKb + " کلو بائٹ۔\n"
                            + "اب پہلے والی اور صاف شدہ آڈیو سُن کر فرق دیکھیں، پھر محفوظ کریں دبائیں۔");
                    btnSave.requestFocus();
                    btnSave.announceForAccessibility("آڈیو صاف ہو گئی۔ اب محفوظ کریں کا بٹن دبائیں۔");
                });
            } catch (Throwable t) {
                runOnUiThread(() -> {
                    busy = false;
                    btnPick.setEnabled(true);
                    btnClean.setEnabled(true);
                    btnSave.setEnabled(cleanedFile != null && cleanedFile.exists());
                    setStatus("معافی، آڈیو صاف نہیں ہو سکی۔ وجہ: " + shortReason(t)
                            + "\nدوسری آڈیو فائل منتخب کر کے دوبارہ کوشش کریں۔");
                    Toast.makeText(MainActivity.this, "صفائی ناکام", Toast.LENGTH_SHORT).show();
                });
            }
        }, "voice-clean").start();
    }

    private static String shortReason(Throwable t) {
        String m = t.getMessage();
        if (m == null) m = t.getClass().getSimpleName();
        return m.length() > 90 ? m.substring(0, 90) : m;
    }

    // ------------------------------------------------------------------ play
    private void play(boolean before) {
        if (before && picked == null) return;
        if (!before && (cleanedFile == null || !cleanedFile.exists())) return;
        stopPlayer(false);
        try {
            player = new MediaPlayer();
            if (before) player.setDataSource(this, picked);
            else player.setDataSource(cleanedFile.getAbsolutePath());
            player.setOnCompletionListener(mp -> stopPlayer(false));
            player.setOnErrorListener((mp, what, extra) -> {
                setStatus("یہ آڈیو چل نہیں سکی۔");
                return false;
            });
            player.prepare();
            player.start();
            btnStop.setVisibility(View.VISIBLE);
            String which = before ? "اصل آڈیو چل رہی ہے" : "صاف شدہ آڈیو چل رہی ہے";
            setStatus(which + "۔ روکنے کے لیے آواز بند کریں دبائیں۔");
            btnStop.announceForAccessibility(which);
        } catch (Exception e) {
            setStatus("آڈیو چلانے میں مسئلہ آیا: " + shortReason(e));
            stopPlayer(false);
        }
    }

    private void stopPlayer(boolean announce) {
        if (player != null) {
            try { if (player.isPlaying()) player.stop(); } catch (Exception ignored) { }
            try { player.release(); } catch (Exception ignored) { }
            player = null;
            if (announce) setStatus("آواز بند کر دی گئی۔");
        }
    }

    // ------------------------------------------------------------------ save
    private void saveAudio() {
        if (cleanedFile == null || !cleanedFile.exists()) {
            setStatus("پہلے آڈیو صاف کریں، پھر محفوظ کریں۔");
            return;
        }
        // Below API 23 permissions are granted at install time; API 29+ uses MediaStore.
        if (Build.VERSION.SDK_INT >= 23 && Build.VERSION.SDK_INT < 29
                && checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE}, REQ_WRITE);
            return;
        }
        doSave();
    }

    @Override
    public void onRequestPermissionsResult(int req, String[] perms, int[] res) {
        super.onRequestPermissionsResult(req, perms, res);
        if (req == REQ_WRITE) {
            if (res.length > 0 && res[0] == PackageManager.PERMISSION_GRANTED) doSave();
            else setStatus("محفوظ کرنے کی اجازت نہیں ملی، اس لیے فائل گیلری میں نہیں جا سکی۔");
        }
    }

    private void doSave() {
        btnSave.setEnabled(false);
        setStatus("محفوظ کیا جا رہا ہے۔ براہ کرم انتظار کریں۔");
        final File src = cleanedFile;
        new Thread(() -> {
            String result = null;
            String failure = null;
            try {
                String stamp = new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date());
                String fileName = "VoiceCleaner_" + stamp + ".mp3";

                if (Build.VERSION.SDK_INT >= 29) {
                    ContentValues cv = new ContentValues();
                    cv.put(MediaStore.Audio.Media.DISPLAY_NAME, fileName);
                    cv.put(MediaStore.Audio.Media.MIME_TYPE, "audio/mpeg");
                    cv.put(MediaStore.Audio.Media.RELATIVE_PATH, Environment.DIRECTORY_MUSIC + "/VoiceCleaner");
                    cv.put(MediaStore.Audio.Media.IS_PENDING, 1);
                    ContentResolver cr = getContentResolver();
                    Uri item = cr.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, cv);
                    if (item == null) throw new Exception("MediaStore insert failed");
                    try (OutputStream os = cr.openOutputStream(item)) {
                        if (os == null) throw new Exception("openOutputStream failed");
                        copy(src, os);
                    }
                    cv.clear();
                    cv.put(MediaStore.Audio.Media.IS_PENDING, 0);
                    cr.update(item, cv, null, null);
                    result = "Music/VoiceCleaner/" + fileName;
                } else {
                    File dir = new File(Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_MUSIC), "VoiceCleaner");
                    if (!dir.exists() && !dir.mkdirs()) throw new Exception("folder create failed");
                    File dst = new File(dir, fileName);
                    try (OutputStream os = new FileOutputStream(dst)) {
                        copy(src, os);
                    }
                    MediaScannerConnection.scanFile(this,
                            new String[]{dst.getAbsolutePath()}, new String[]{"audio/mpeg"}, null);
                    result = dst.getAbsolutePath();
                }
            } catch (Throwable t) {
                failure = shortReason(t);
            }

            final String ok = result;
            final String err = failure;
            runOnUiThread(() -> {
                btnSave.setEnabled(true);
                if (ok != null) {
                    lastSaved = ok;
                    setStatus("محفوظ ہو گئی۔\n" + ok + "\nاب یہ فائل آپ کے میوزک اور گیلری میں موجود ہے۔");
                    btnSave.announceForAccessibility("آڈیو محفوظ ہو گئی، میوزک فولڈر میں وائس کلینر کے اندر۔");
                    Toast.makeText(this, "محفوظ ہو گئی", Toast.LENGTH_SHORT).show();
                } else {
                    setStatus("محفوظ نہیں ہو سکی۔ وجہ: " + err);
                }
            });
        }, "voice-save").start();
    }

    private static void copy(File src, OutputStream os) throws Exception {
        try (FileInputStream in = new FileInputStream(src)) {
            byte[] b = new byte[16384];
            int n;
            while ((n = in.read(b)) > 0) os.write(b, 0, n);
            os.flush();
        }
    }

    // ------------------------------------------------------------------ misc
    private void setStatus(String s) {
        status.setText(s);
        if (Build.VERSION.SDK_INT >= 16) status.announceForAccessibility(s);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        stopPlayer(false);
    }
}
