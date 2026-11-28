package com.parallaxnews.parallax_news

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.common.util.concurrent.ListenableFuture
import com.google.mlkit.genai.common.DownloadCallback
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.genai.prompt.java.GenerativeModelFutures
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

/**
 * On-device summaries with Gemini Nano through Android AICore, using the
 * ML Kit GenAI Prompt API (Google's current API for Nano; it supports newer
 * phones such as the Galaxy S26 series). Nothing leaves the phone.
 *
 * Channel "parallax/genai":
 *   status()              -> "available" | "downloadable" | "downloading" | "unavailable:<reason>"
 *   summarize(text, n)    -> String (n = 1..3 bullets, one per line)
 */
object GenAiBridge {
    private const val CHANNEL = "parallax/genai"
    private const val MAX_CHARS = 9000 // leaves room for the prompt inside the ~4000-token window
    private val main = Handler(Looper.getMainLooper())
    private val onMain = Executor { r -> main.post(r) }
    private var model: GenerativeModelFutures? = null

    private fun model(): GenerativeModelFutures =
        model ?: GenerativeModelFutures.from(Generation.getClient()).also { model = it }

    @Suppress("UNUSED_PARAMETER")
    fun register(context: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> {
                    val m = try {
                        model()
                    } catch (e: Throwable) {
                        result.success("unavailable:${reason(e)}")
                        return@setMethodCallHandler
                    }
                    whenDone(m.checkStatus(), { code -> result.success(name(code)) }, { e ->
                        result.success("unavailable:${reason(e)}")
                    })
                }
                "summarize" -> {
                    val text = (call.argument<String>("text") ?: "").take(MAX_CHARS)
                    val bullets = (call.argument<Int>("bullets") ?: 3).coerceIn(1, 3)
                    summarize(text, bullets, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun summarize(text: String, bullets: Int, result: MethodChannel.Result) {
        val m = try {
            model()
        } catch (e: Throwable) {
            result.error("unavailable", reason(e), null)
            return
        }
        whenDone(m.checkStatus(), { code ->
            when (code) {
                FeatureStatus.AVAILABLE -> generate(m, text, bullets, result)
                FeatureStatus.DOWNLOADABLE -> m.download(object : DownloadCallback {
                    override fun onDownloadCompleted() {
                        main.post { generate(m, text, bullets, result) }
                    }
                    override fun onDownloadFailed(e: GenAiException) {
                        main.post { result.error("unavailable", reason(e), null) }
                    }
                    override fun onDownloadProgress(bytes: Long) {}
                    override fun onDownloadStarted(bytes: Long) {}
                })
                FeatureStatus.DOWNLOADING -> result.error("downloading", "The model is still downloading.", null)
                else -> result.error("unavailable", name(code).substringAfter(':'), null)
            }
        }, { e -> result.error("unavailable", reason(e), null) })
    }

    private fun generate(m: GenerativeModelFutures, text: String, bullets: Int, result: MethodChannel.Result) {
        val prompt = "Summarize the news coverage below in exactly $bullets short bullet points. " +
            "Start each bullet with \"- \". Use only facts stated in the text. " +
            "Do not add opinions, guesses or a title.\n\nCoverage:\n$text"
        val request = try {
            generateContentRequest(TextPart(prompt)) {
                temperature = 0.2f
            }
        } catch (e: Throwable) {
            result.error("failed", reason(e), null)
            return
        }
        whenDone(m.generateContent(request), { r ->
            val out = r.candidates.firstOrNull()?.text
            if (out.isNullOrBlank()) result.error("failed", "The model returned no text.", null) else result.success(out)
        }, { e -> result.error("failed", reason(e), null) })
    }

    /** Runs [onOk]/[onErr] on the main thread once the future completes. */
    private fun <T> whenDone(future: ListenableFuture<T>, onOk: (T) -> Unit, onErr: (Throwable) -> Unit) {
        future.addListener({
            try {
                onOk(future.get())
            } catch (e: Exception) {
                onErr(e.cause ?: e)
            }
        }, onMain)
    }

    private fun reason(e: Throwable): String = e.message?.takeIf { it.isNotBlank() } ?: e.javaClass.simpleName

    private fun name(code: Int): String = when (code) {
        FeatureStatus.AVAILABLE -> "available"
        FeatureStatus.DOWNLOADABLE -> "downloadable"
        FeatureStatus.DOWNLOADING -> "downloading"
        FeatureStatus.UNAVAILABLE -> "unavailable:AICore reports Gemini Nano is not supported or not set up yet on this phone"
        else -> "unavailable:unknown AICore status $code"
    }
}
