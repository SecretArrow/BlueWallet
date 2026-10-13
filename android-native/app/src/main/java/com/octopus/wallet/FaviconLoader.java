package com.octopus.wallet;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.util.LruCache;
import android.view.View;
import android.widget.ImageView;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Startpage favicon loader. Favicons are fetched off the main thread with strict size/time budgets
 * and cached per host; the letter avatar in {@code item_recent_visit.xml} remains the fallback
 * whenever a favicon is unavailable (load failures leave the target untouched).
 *
 * <p>URL resolution lives in {@link FaviconUrls} (pure, JVM-testable). This class only does
 * Android-bound work and is never touched by unit tests.
 */
public final class FaviconLoader {

  private static final String TAG = "FaviconLoader";
  private static final int CONNECT_TIMEOUT_MS = 8000;
  private static final int READ_TIMEOUT_MS = 8000;
  private static final int MAX_BYTES = 512 * 1024;
  private static final int CACHE_MAX_BYTES = 4 * 1024 * 1024;
  private static final int DEFAULT_SIZE_PX = 42;
  private static final String USER_AGENT =
      "Mozilla/5.0 (Linux; Android 10) OctraWallet/1.0 (favicon)";

  private static final ThreadPoolExecutor EXECUTOR =
      new ThreadPoolExecutor(
          2,
          2,
          30L,
          TimeUnit.SECONDS,
          new LinkedBlockingQueue<>(),
          new ThreadFactory() {
            private final AtomicInteger counter = new AtomicInteger(1);

            @Override
            public Thread newThread(Runnable r) {
              Thread t = new Thread(r, "favicon-" + counter.getAndIncrement());
              t.setDaemon(true);
              return t;
            }
          });

  private static final LruCache<String, Bitmap> CACHE =
      new LruCache<String, Bitmap>(CACHE_MAX_BYTES) {
        @Override
        protected int sizeOf(String key, Bitmap value) {
          return value == null ? 0 : value.getByteCount();
        }
      };

  static {
    EXECUTOR.allowCoreThreadTimeOut(true);
  }

  private FaviconLoader() {}

  /**
   * Stops the (daemon) fetch pool. Nothing in the app calls this — the threads are daemons so
   * process exit is never blocked — but the hook is kept for tests and future lifecycle wiring.
   */
  public static void shutdown() {
    EXECUTOR.shutdown();
  }

  /**
   * Loads the favicon for {@code pageUrl} into {@code target}. The view's tag is set to the page
   * URL first; the delivered bitmap is only applied if the tag still matches (view not re-bound or
   * recycled meanwhile). Failures are silent — the letter-avatar fallback stays visible.
   */
  public static void loadAsync(String pageUrl, ImageView target, int sizePx) {
    if (target == null || pageUrl == null) {
      return;
    }
    final String requestKey = pageUrl.trim();
    if (requestKey.isEmpty()) {
      return;
    }
    final String faviconUrl = FaviconUrls.faviconUrlFor(requestKey);
    if (faviconUrl.isEmpty()) {
      // Non-http(s) or unparsable — keep the fallback avatar.
      return;
    }
    final String host = FaviconUrls.hostOf(requestKey);
    if (host.isEmpty()) {
      return;
    }
    target.setTag(requestKey);

    Bitmap cached = CACHE.get(host);
    if (cached != null) {
      deliver(target, cached, requestKey);
      return;
    }
    final int boundedSize = sizePx > 0 ? sizePx : DEFAULT_SIZE_PX;
    EXECUTOR.execute(
        () -> {
          Bitmap bitmap = fetch(faviconUrl, boundedSize);
          if (bitmap == null) {
            return;
          }
          CACHE.put(host, bitmap);
          deliver(target, bitmap, requestKey);
        });
  }

  private static void deliver(
      final ImageView target, final Bitmap bitmap, final String requestKey) {
    try {
      Handler main = new Handler(Looper.getMainLooper());
      main.post(
          () -> {
            try {
              if (target == null) {
                return;
              }
              Object tag = target.getTag();
              if (tag == null || !tag.equals(requestKey)) {
                // View was re-bound or recycled — never show a stale icon.
                return;
              }
              target.setImageBitmap(bitmap);
              target.setVisibility(View.VISIBLE);
            } catch (Exception e) {
              // Recycled/detached views can throw here; log, never crash.
              Log.w(TAG, "Favicon delivery failed: " + e);
            }
          });
    } catch (Exception e) {
      Log.w(TAG, "Favicon main-thread post failed: " + e);
    }
  }

  private static Bitmap fetch(String faviconUrl, int sizePx) {
    HttpURLConnection conn = null;
    try {
      conn = (HttpURLConnection) new URL(faviconUrl).openConnection();
      conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
      conn.setReadTimeout(READ_TIMEOUT_MS);
      conn.setInstanceFollowRedirects(true);
      conn.setRequestProperty("User-Agent", USER_AGENT);
      conn.setRequestProperty("Accept", "image/*,*/*;q=0.8");
      int code = conn.getResponseCode();
      if (code < 200 || code >= 300) {
        return null;
      }
      byte[] raw = readBounded(conn.getInputStream());
      if (raw == null || raw.length == 0) {
        return null;
      }
      // Content-type is advisory only: many servers mislabel favicons.
      // Accept either a declared image/* or a successful decode attempt.
      return decode(raw, sizePx);
    } catch (IOException | RuntimeException e) {
      Log.w(TAG, "Favicon fetch failed for " + faviconUrl + ": " + e);
      return null;
    } finally {
      if (conn != null) {
        conn.disconnect();
      }
    }
  }

  /** Reads at most {@link #MAX_BYTES} bytes; returns null if the body is larger. */
  private static byte[] readBounded(InputStream in) throws IOException {
    if (in == null) {
      return null;
    }
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    byte[] buf = new byte[8192];
    int total = 0;
    int n;
    while ((n = in.read(buf)) != -1) {
      total += n;
      if (total > MAX_BYTES) {
        return null;
      }
      out.write(buf, 0, n);
    }
    return out.toByteArray();
  }

  private static Bitmap decode(byte[] raw, int sizePx) {
    BitmapFactory.Options probe = new BitmapFactory.Options();
    probe.inJustDecodeBounds = true;
    BitmapFactory.decodeByteArray(raw, 0, raw.length, probe);
    if (probe.outWidth <= 0 || probe.outHeight <= 0) {
      return null; // Payload is not a decodable image.
    }
    BitmapFactory.Options opts = new BitmapFactory.Options();
    opts.inSampleSize = sampleSizeFor(probe.outWidth, probe.outHeight, sizePx);
    try {
      return BitmapFactory.decodeByteArray(raw, 0, raw.length, opts);
    } catch (Exception e) {
      Log.w(TAG, "Favicon decode failed: " + e);
      return null;
    }
  }

  private static int sampleSizeFor(int width, int height, int target) {
    int sample = 1;
    while (width / (sample * 2) >= target && height / (sample * 2) >= target) {
      sample *= 2;
    }
    return sample;
  }
}
