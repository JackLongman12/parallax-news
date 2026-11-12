package com.parallaxnews.parallax_news

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
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
            views.setTextViewText(R.id.updated, widgetData.getString("updated", "Open the app to load your briefing"))
            for (i in titles.indices) {
                if (i < items.length()) {
                    val o = items.getJSONObject(i)
                    views.setViewVisibility(titles[i], View.VISIBLE)
                    views.setViewVisibility(metas[i], View.VISIBLE)
                    views.setTextViewText(titles[i], o.optString("t"))
                    views.setTextViewText(metas[i], coverageLine(o))
                } else {
                    views.setViewVisibility(titles[i], View.GONE)
                    views.setViewVisibility(metas[i], View.GONE)
                }
            }
            views.setOnClickPendingIntent(R.id.root, launch(context, "briefing"))
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

/** Blindspot: the top story one side of the spectrum is ignoring. */
class BlindspotWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val o = try { JSONObject(widgetData.getString("blindspot", "{}")) } catch (e: Exception) { JSONObject() }
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_blindspot)
            if (o.has("t")) {
                views.setTextViewText(R.id.label, "BLINDSPOT · missed by the ${o.optString("side")}")
                views.setTextViewText(R.id.title, o.optString("t"))
                views.setTextViewText(R.id.meta, coverageLine(o))
            } else {
                views.setTextViewText(R.id.label, "BLINDSPOT")
                views.setTextViewText(R.id.title, "No blindspots right now")
                views.setTextViewText(R.id.meta, "Open the app to refresh")
            }
            views.setOnClickPendingIntent(R.id.root, launch(context, "blindspot"))
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
