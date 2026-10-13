package github.com.maragung.octopus_wallet

import android.content.Intent
import android.os.Handler
import android.os.Looper

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * App entry activity. In addition to hosting the Flutter UI it forwards
 * deep links (octra:// / octra-wallet:// intent filters, launchMode =
 * singleTop) to the Dart side over the MethodChannel
 * 'github.com.maragung.octopus_wallet/deeplink' as 'onDeepLink' calls
 * (payload: the link URI as a string).
 */
class MainActivity : FlutterFragmentActivity() {
    private var deeplinkChannel: MethodChannel? = null

    /**
     * Deep link carried by the intent that launched the activity (cold
     * start). Served exactly once — consumed by whichever delivery path
     * wins (push below or the Dart-side pull) so the link is never
     * dispatched twice.
     */
    private var initialLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deeplinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "github.com.maragung.octopus_wallet/deeplink"
        )

        // Dart pulls the cold-start link once its handler is registered
        // (DeepLinkService.checkInitialLink). Read-once semantics keep the
        // push + pull pair race-free.
        deeplinkChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialLink") {
                val link = initialLink
                initialLink = null
                result.success(link)
            } else {
                result.notImplemented()
            }
        }

        // Cold-start deep link: the launching intent may already carry
        // data. Invoked via a main-thread Handler post (not inline) to give
        // the Dart isolate a chance to run and register its method-call
        // handler first — invoking synchronously here would drop the link,
        // because no handler exists yet. If the post still races ahead of
        // Dart startup, the pull above recovers the link.
        val launchLink = intent?.data?.toString()
        if (launchLink != null) {
            initialLink = launchLink
            Handler(Looper.getMainLooper()).post {
                val link = initialLink
                if (link != null) {
                    initialLink = null
                    deeplinkChannel?.invokeMethod("onDeepLink", link)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTop launch mode: warm deep links re-deliver to this
        // existing activity instance instead of creating a new one.
        setIntent(intent)
        val data = intent.data
        if (data != null) {
            // Main-thread post (we are already on the main thread) keeps
            // the delivery consistent with the cold-start path above; the
            // null-Channel guard covers teardown edge cases.
            Handler(Looper.getMainLooper()).post {
                deeplinkChannel?.invokeMethod("onDeepLink", data.toString())
            }
        }
    }
}
