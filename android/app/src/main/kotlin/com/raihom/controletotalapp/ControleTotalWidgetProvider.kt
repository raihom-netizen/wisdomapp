package com.wisdomapp.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/// Widget premium — shell + lista; fail-safe instantâneo se JSON falhar.
class ControleTotalWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences,
    ) {
        WidgetPayloadRollover.maybeRollover(context)
        appWidgetIds.forEach { widgetId ->
            val views = try {
                buildListWidget(context, widgetData, widgetId)
            } catch (_: Throwable) {
                buildFailSafeWidget(context, widgetData)
            }
            try {
                attachClickOpenApp(context, views, widgetData)
            } catch (_: Throwable) {
            }
            try {
                appWidgetManager.updateAppWidget(widgetId, views)
                appWidgetManager.notifyAppWidgetViewDataChanged(
                    widgetId,
                    R.id.widget_events_list,
                )
            } catch (_: Throwable) {
            }
        }
    }

    private fun buildFailSafeWidget(
        context: Context,
        widgetData: android.content.SharedPreferences,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_list_container)
        views.setTextViewText(R.id.wdb_brand, context.getString(R.string.widget_brand_name))
        views.setTextViewText(R.id.wdb_hint, "Toque para abrir")
        views.setViewVisibility(R.id.wdb_updated, View.GONE)
        views.setViewVisibility(R.id.widget_events_list, View.GONE)
        views.setViewVisibility(R.id.widget_list_empty, View.VISIBLE)
        views.setTextViewText(
            R.id.widget_empty_text,
            "Sem compromissos para hoje",
        )
        return views
    }

    private fun attachClickOpenApp(
        context: Context,
        views: RemoteViews,
        widgetData: android.content.SharedPreferences,
    ) {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val module = resolveOpenModule(widgetData)
        val launch = Intent(context, MainActivity::class.java).apply {
            setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_OPEN_MODULE, module)
        }
        val pi = PendingIntent.getActivity(context, module, launch, flags)
        views.setOnClickPendingIntent(R.id.widget_root, pi)
    }

    private fun resolveOpenModule(widgetData: android.content.SharedPreferences): Int {
        val fromWidget = widgetData.getInt("widget_open_module", -1)
        if (fromWidget in 0..9) return fromWidget
        val fromFlutter = widgetData.getInt("flutter.home_start_mod_idx_v1", -1)
        if (fromFlutter in 0..9) return fromFlutter
        return OPEN_MODULE_HOME
    }

    private fun buildListWidget(
        context: Context,
        widgetData: android.content.SharedPreferences,
        appWidgetId: Int,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_list_container)

        var brand = context.getString(R.string.widget_brand_name)
        var hint = "Toque para abrir"
        var updated = ""
        var hasRows = false

        val jsonRaw = widgetData.getString(JSON_KEY, null)
        if (!jsonRaw.isNullOrBlank()) {
            try {
                val root = JSONObject(jsonRaw)
                brand = root.optString("brand", brand)
                hint = root.optString("hint", hint)
                updated = root.optString("updated", root.optString("updatedAt", ""))
                val rows = root.optJSONArray("rows")
                hasRows = rows != null && rows.length() > 0
                if (!hasRows) {
                    val legacy = root.optJSONArray("listItems")
                    hasRows = legacy != null && legacy.length() > 0
                }
            } catch (_: Throwable) {
                return buildFailSafeWidget(context, widgetData)
            }
        }

        views.setTextViewText(R.id.wdb_brand, brand)
        views.setTextViewText(R.id.wdb_hint, hint)
        if (updated.isNotBlank()) {
            views.setViewVisibility(R.id.wdb_updated, View.VISIBLE)
            views.setTextViewText(R.id.wdb_updated, updated)
        } else {
            views.setViewVisibility(R.id.wdb_updated, View.GONE)
        }

        if (!hasRows) {
            views.setViewVisibility(R.id.widget_events_list, View.GONE)
            views.setViewVisibility(R.id.widget_list_empty, View.VISIBLE)
            views.setTextViewText(
                R.id.widget_list_empty,
                "Sem compromissos para hoje",
            )
            return views
        }

        views.setViewVisibility(R.id.widget_events_list, View.VISIBLE)
        views.setViewVisibility(R.id.widget_list_empty, View.GONE)

        val serviceIntent = Intent(context, ControleTotalWidgetService::class.java).apply {
            putExtra(EXTRA_WIDGET_ID, appWidgetId)
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
        }

        @Suppress("DEPRECATION")
        views.setRemoteAdapter(R.id.widget_events_list, serviceIntent)
        views.setEmptyView(R.id.widget_events_list, R.id.widget_list_empty)

        return views
    }

    companion object {
        const val JSON_KEY = "widget_events_json"
        const val EXTRA_WIDGET_ID = "ct_widget_id"
        const val EXTRA_OPEN_MODULE = "ct_open_module"
        const val OPEN_MODULE_HOME = 0
        const val OPEN_MODULE_SCALES = 3
    }
}

