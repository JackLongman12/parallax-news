package com.parallaxnews.parallax_news

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.graphics.Color
import android.net.Uri
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject

private val LEFT = Color.parseColor("#3D6BFF")
private val CENTER = Color.parseColor("#A08CFF")
private val RIGHT = Color.parseColor("#FF4D6D")

/** "● 40% ● 20% ● 40%  ·  5 sources" with coloured dots. */
private fun coverageLine(o: JSONObject): CharSequence {
    val l = o.optInt("l"); val c = o.optInt("c"); val r = o.optInt("r")
    val rated = (l + c + r).coerceAtLeast(1)
    val sb = SpannableStringBuilder()
    fun part(color: Int, n: Int) {
        val start = sb.length
        sb.append("●")
        sb.setSpan(ForegroundColorSpan(color), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        sb.append(" ${n * 100 / rated}%  ")
    }
    if (l + c + r > 0) { part(LEFT, l); part(CENTER, c); part(RIGHT, r) }
    sb.append("${o.optInt("n")} sources · ${o.optString("cat")}")
    return sb
}

/** Current widget height in dp (changes as the user resizes it). */
private fun heightDp(mgr: AppWidgetManager, id: Int): Int =
    mgr.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 180)

private fun widthDp(mgr: AppWidgetManager, id: Int): Int =
    mgr.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 250)

private fun launch(context: Context, path: String) =
    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("parallax://$path"))

/** Daily Briefing: top 4 curated stories. Tap anywhere to open "For You". */
class BriefingWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val items = try { JSONArray(widgetData.getString("briefing", "[]")) } catch (e: Exception) { JSONArray() }
        val titles = intArrayOf(R.id.title_0, R.id.title_1, R.id.title_2, R.id.title_3)
        val metas = intArrayOf(R.id.meta_0, R.id.meta_1, R.id.meta_2, R.id.meta_3)
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_briefing)
            // Responsive: show as many stories as fit the size the user picked.
            val h = heightDp(appWidgetManager, id)
            val rows = when {
                h < 110 -> 1
                h < 170 -> 2
                h < 240 -> 3
                else -> 4
            }
            val compact = h < 110 || widthDp(appWidgetManager, id) < 200
            views.setViewVisibility(R.id.header, if (h < 90) View.GONE else View.VISIBLE)
            views.setViewVisibility(R.id.updated, if (compact) View.GONE else View.VISIBLE)
            views.setTextViewText(R.id.updated, widgetData.getString("updated", "Open the app to load your briefing"))
            for (i in titles.indices) {
                if (i < items.length() && i < rows) {
                    val o = items.getJSONObject(i)
                    views.setViewVisibility(titles[i], View.VISIBLE)
                    views.setViewVisibility(metas[i], View.VISIBLE)
                    views.setTextViewText(titles[i], o.optString("t"))
                    views.setTextViewText(metas[i], coverageLine(o))
                    views.setViewVisibility(metas[i], if (compact && rows == 1) View.GONE else View.VISIBLE)
                } else {
                    views.setViewVisibility(titles[i], View.GONE)
                    views.setViewVisibility(metas[i], View.GONE)
                }
            }
            views.setOnClickPendingIntent(R.id.root, launch(context, "briefing"))
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, mgr: AppWidgetManager, id: Int, newOptions: Bundle) {
        super.onAppWidgetOptionsChanged(context, mgr, id, newOptions)
        onUpdate(context, mgr, intArrayOf(id), HomeWidgetPlugin.getData(context))
    }
}
