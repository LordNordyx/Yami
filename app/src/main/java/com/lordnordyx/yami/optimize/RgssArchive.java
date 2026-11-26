package com.lordnordyx.yami.optimize;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Reader for RGSS encrypted archives.
 * <ul>
 *   <li>v1 — Game.rgssad (XP) / Game.rgss2a (VX): rolling key 0xDEADCAFE, k = k*7+3</li>
 *   <li>v3 — Game.rgss3a (VX Ace): seeded key, offset table, per-file keys</li>
 * </ul>
 * Extracting to loose files removes per-read decryption, lets the path index
 * see every file, and enables hi-res texture packs.
 * (Plain Java so the parser can be unit-tested without the Android toolchain.)
 */
public final class RgssArchive {

    public static final class Entry {
        public final String name;
        public final long offset;
        public final int size;
        public final int key;

        Entry(String name, long offset, int size, int key) {
            this.name = name; this.offset = offset; this.size = size; this.key = key;
        }
    }

    public interface Progress { void onProgress(int done, int total, String name); }

    private final File file;
    public final int version;
    public final List<Entry> entries;

    public RgssArchive(File file) throws IOException {
        this.file = file;
        try (RandomAccessFile raf = new RandomAccessFile(file, "r")) {
            byte[] magic = new byte[8];
            raf.readFully(magic);
            if (!new String(magic, 0, 6, StandardCharsets.US_ASCII).equals("RGSSAD"))
                throw new IOException("Not an RGSS archive");
            version = magic[7];
            if (version == 1) entries = readV1(raf);
            else if (version == 3) entries = readV3(raf);
            else throw new IOException("Unsupported RGSSAD version " + version);
        }
    }

    private static int readIntLE(RandomAccessFile raf) throws IOException {
        byte[] b = new byte[4];
        raf.readFully(b);
        return (b[0] & 0xFF) | ((b[1] & 0xFF) << 8) | ((b[2] & 0xFF) << 16) | ((b[3] & 0xFF) << 24);
    }

    private static List<Entry> readV1(RandomAccessFile raf) throws IOException {
        List<Entry> out = new ArrayList<>();
        int key = 0xDEADCAFE;
        long len = raf.length();
        while (raf.getFilePointer() + 4 <= len) {
            int nameLen = readIntLE(raf) ^ key;
            key = key * 7 + 3;
            if (nameLen <= 0 || nameLen > 4096) break;
            byte[] name = new byte[nameLen];
            raf.readFully(name);
            for (int i = 0; i < nameLen; i++) {
                name[i] = (byte) (name[i] ^ (key & 0xFF));
                key = key * 7 + 3;
            }
            int size = readIntLE(raf) ^ key;
            key = key * 7 + 3;
            long offset = raf.getFilePointer();
            if (size < 0 || offset + size > len) break;
            out.add(new Entry(decodeName(name), offset, size, key));
            raf.seek(offset + size);
        }
        return Collections.unmodifiableList(out);
    }

    private static List<Entry> readV3(RandomAccessFile raf) throws IOException {
        List<Entry> out = new ArrayList<>();
        int key = readIntLE(raf) * 9 + 3;
        long len = raf.length();
        while (raf.getFilePointer() + 16 <= len) {
            int offset = readIntLE(raf) ^ key;
            if (offset == 0) break;
            int size = readIntLE(raf) ^ key;
            int fileKey = readIntLE(raf) ^ key;
            int nameLen = readIntLE(raf) ^ key;
            if (nameLen <= 0 || nameLen > 4096) break;
            byte[] name = new byte[nameLen];
            raf.readFully(name);
            for (int i = 0; i < nameLen; i++) {
                name[i] = (byte) (name[i] ^ ((key >>> (8 * (i % 4))) & 0xFF));
            }
            out.add(new Entry(decodeName(name), offset & 0xFFFFFFFFL, size, fileKey));
        }
        return Collections.unmodifiableList(out);
    }

    private static String decodeName(byte[] b) {
        String s;
        try {
            s = StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(b)).toString();
        } catch (CharacterCodingException e) {
            s = new String(b, Charset.forName("Shift_JIS"));
        }
        return s.replace('\\', '/');
    }

    /** Both versions decrypt file data with a 4-byte XOR stream, key advancing k = k*7+3. */
    public void extract(Entry e, OutputStream os) throws IOException {
        try (RandomAccessFile raf = new RandomAccessFile(file, "r")) {
            raf.seek(e.offset);
            int key = e.key;
            int remaining = e.size;
            byte[] buf = new byte[1 << 16]; // multiple of 4 keeps key alignment per chunk
            while (remaining > 0) {
                int n = Math.min(buf.length, remaining);
                raf.readFully(buf, 0, n);
                for (int i = 0; i < n; i++) {
                    buf[i] = (byte) (buf[i] ^ ((key >>> (8 * (i & 3))) & 0xFF));
                    if ((i & 3) == 3) key = key * 7 + 3;
                }
                os.write(buf, 0, n);
                remaining -= n;
            }
        }
    }

    public void extract(Entry e, File dest) throws IOException {
        File parent = dest.getParentFile();
        if (parent != null) parent.mkdirs();
        File tmp = new File(dest.getPath() + ".part");
        try (OutputStream os = new BufferedOutputStream(new FileOutputStream(tmp), 1 << 16)) {
            extract(e, os);
        }
        if (!tmp.renameTo(dest)) throw new IOException("rename failed: " + dest);
    }

    /** @return number of files written */
    public int extractAll(File destDir, boolean overwrite, Progress progress) throws IOException {
        String base = destDir.getCanonicalPath() + File.separator;
        int written = 0;
        for (int i = 0; i < entries.size(); i++) {
            Entry e = entries.get(i);
            File out = new File(destDir, e.name);
            if (!out.getCanonicalPath().startsWith(base)) continue; // path traversal guard
            if (overwrite || !out.exists()) { extract(e, out); written++; }
            if (progress != null) progress.onProgress(i + 1, entries.size(), e.name);
        }
        return written;
    }

    public static File find(File gameDir) {
        File[] files = gameDir.listFiles();
        if (files == null) return null;
        for (File f : files) {
            String n = f.getName().toLowerCase();
            if (f.isFile() && (n.equals("game.rgssad") || n.equals("game.rgss2a") || n.equals("game.rgss3a")))
                return f;
        }
        return null;
    }
}
