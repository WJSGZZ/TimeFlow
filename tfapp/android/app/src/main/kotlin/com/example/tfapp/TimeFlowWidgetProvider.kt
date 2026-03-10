package com.example.tfapp

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.*

class TimeFlowWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) updateAppWidget(context, mgr, id)
    }

    companion object {

        data class CourseIds(val container: Int, val name: Int, val room: Int, val time: Int)

        fun updateAppWidget(context: Context, mgr: AppWidgetManager, widgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.timeflow_widget)

            val now = Calendar.getInstance()
            val tmr = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1) }

            // 日期格式：3.9 Mon
            val dateFmt = SimpleDateFormat("M.d", Locale.ENGLISH)
            val dayFmt = SimpleDateFormat("EEE", Locale.ENGLISH)
            val todayStr = "${dateFmt.format(now.time)} ${dayFmt.format(now.time)}"
            val tmrStr = "${dateFmt.format(tmr.time)} ${dayFmt.format(tmr.time)}"

            views.setTextViewText(R.id.today_header, todayStr)
            views.setTextViewText(R.id.tomorrow_header, tmrStr)

            // 点击跳转App
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pendingIntent = PendingIntent.getActivity(
                context, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            val prefs = HomeWidgetPlugin.getData(context)

            // 周次
            val week = prefs.getInt("widget_week", 0)
            views.setTextViewText(R.id.week_label, if (week > 0) "第${week}周" else "")

            fillDay(views,
                prefs.getString("widget_today", null),
                listOf(
                    CourseIds(R.id.today_course1, R.id.today_c1_name, R.id.today_c1_room, R.id.today_c1_time),
                    CourseIds(R.id.today_course2, R.id.today_c2_name, R.id.today_c2_room, R.id.today_c2_time),
                ),
                R.id.today_empty
            )

            fillDay(views,
                prefs.getString("widget_tomorrow", null),
                listOf(
                    CourseIds(R.id.tomorrow_course1, R.id.tomorrow_c1_name, R.id.tomorrow_c1_room, R.id.tomorrow_c1_time),
                    CourseIds(R.id.tomorrow_course2, R.id.tomorrow_c2_name, R.id.tomorrow_c2_room, R.id.tomorrow_c2_time),
                ),
                R.id.tomorrow_empty
            )

            mgr.updateAppWidget(widgetId, views)
        }

        private fun fillDay(views: RemoteViews, json: String?, ids: List<CourseIds>, emptyId: Int) {
            if (json == null) { showEmpty(views, ids, emptyId); return }
            try {
                val arr = JSONArray(json)
                if (arr.length() == 0) { showEmpty(views, ids, emptyId); return }
                views.setViewVisibility(emptyId, View.GONE)
                for (i in ids.indices) {
                    if (i < arr.length()) {
                        val obj = arr.getJSONObject(i)
                        val color = Color.parseColor("#${obj.optString("color", "FFD4907A")}")
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            views.setColorStateList(ids[i].container, "setBackgroundTintList",
                                ColorStateList.valueOf(color))
                        } else {
                            views.setInt(ids[i].container, "setBackgroundColor", color)
                        }
                        views.setTextViewText(ids[i].name, obj.optString("name", ""))
                        views.setTextViewText(ids[i].room, obj.optString("room", ""))
                        views.setTextViewText(ids[i].time, obj.optString("time", ""))
                        views.setViewVisibility(ids[i].container, View.VISIBLE)
                    } else {
                        views.setViewVisibility(ids[i].container, View.GONE)
                    }
                }
            } catch (e: Exception) { showEmpty(views, ids, emptyId) }
        }

        private fun showEmpty(views: RemoteViews, ids: List<CourseIds>, emptyId: Int) {
            views.setViewVisibility(emptyId, View.VISIBLE)
            ids.forEach { views.setViewVisibility(it.container, View.GONE) }
        }
    }
}