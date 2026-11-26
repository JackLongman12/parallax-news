package com.parallaxnews.parallax_news

import android.content.Context
import com.google.mlkit.genai.common.DownloadCallback
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.summarization.SummarizationRequest
import com.google.mlkit.genai.summarization.Summarization
import com.google.mlkit.genai.summarization.Summarizer
import com.google.mlkit.genai.summarization.SummarizerOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * On-device summaries with Gemini Nano through Android AICore (ML Kit GenAI
 * Summarization). Nothing leaves the phone. Devices without AICore or Gemini
 * Nano report "unavailable"; the Dart side then hides the feature.
 *
 * Channel "parallax/genai":
 *   status()              -> "available" | "downloadable" | "downloading" | "unavailable"
 *   summarize(text, n)    -> String (n = 1..3 bullets, one per line)
 */
object GenAiBridge {
    private const val CHANNEL = "parallax/genai"
    private const val MAX_CHARS = 12000 // well under the model's 4000-token input limit

    fun register(context: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> {
                    val s = client(context, 1)
                    s.checkFeatureStatus()
                        .addOnSuccessListener { code -> s.close(); result.success(name(code)) }
                        .addOnFailureListener { s.close(); result.success("unavailable") }
                }
                "summarize" -> {
                    val text = (call.argument<String>("text") ?: "").take(MAX_CHARS)
                    val bullets = (call.argument<Int>("bullets") ?: 3).coerceIn(1, 3)
                    summarize(context, text, bullets, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun summarize(context: Context, text: String, bullets: Int, result: MethodChannel.Result) {
        val s = client(context, bullets)
        s.checkFeatureStatus().addOnSuccessListener { code ->
            when (code) {
                FeatureStatus.AVAILABLE -> infer(s, text, result)
                FeatureStatus.DOWNLOADABLE -> s.downloadFeature(object : DownloadCallback {
                    override fun onDownloadCompleted() = infer(s, text, result)
                    override fun onDownloadFailed(e: com.google.mlkit.common.MlKitException) {
                        s.close(); result.error("unavailable", e.message, null)
                    }
                    override fun onDownloadProgress(bytes: Long) {}
                    override fun onDownloadStarted(bytes: Long) {}
                })
                else -> { s.close(); result.error("unavailable", name(code), null) }
            }
        }.addOnFailureListener { e -> s.close(); result.error("unavailable", e.message, null) }
    }

    private fun infer(s: Summarizer, text: String, result: MethodChannel.Result) {
        s.runInference(SummarizationRequest.builder(text).build())
            .addOnSuccessListener { r -> s.close(); result.success(r.summary) }
            .addOnFailureListener { e -> s.close(); result.error("failed", e.message, null) }
    }

    private fun client(context: Context, bullets: Int): Summarizer {
        val output = when (bullets) {
            1 -> SummarizerOptions.OutputType.ONE_BULLET
            2 -> SummarizerOptions.OutputType.TWO_BULLETS
            else -> SummarizerOptions.OutputType.THREE_BULLETS
        }
        val options = SummarizerOptions.builder(context)
            .setInputType(SummarizerOptions.InputType.ARTICLE)
            .setOutputType(output)
            .setLanguage(SummarizerOptions.Language.ENGLISH)
            .build()
        return Summarization.getClient(options)
    }

    private fun name(code: Int): String = when (code) {
        FeatureStatus.AVAILABLE -> "available"
        FeatureStatus.DOWNLOADABLE -> "downloadable"
        FeatureStatus.DOWNLOADING -> "downloading"
        else -> "unavailable"
    }
}
