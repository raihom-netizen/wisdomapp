package com.wisdomapp.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

/// Widget compacto 2×2 — calendário do dia + preview de amanhã (estilo iOS Calendários).
class ControleTotalWidgetSmallProvider : es.antonborri.home_widget.HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences,
    ) {
        WidgetPayloadRollover.maybeRollover(context)
        appWidgetIds.forEach { widgetId ->
            val views = try {
                buildSmallWidget(context, widgetData)
            } catch (_: Throwable) {
                buildFailSafe(context)
            }
            try {
                attachClickOpenApp(context, views, widgetData)
            } catch (_: Throwable) {
            }
            try {
                appWidgetManager.updateAppWidget(widgetId, views)
            } catch (_: Throwable) {
            }
        }
    }

    private fun buildFailSafe(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_calendar_small)
        views.setTextViewText(R.id.wcs_day_num, "?")
        views.setTextViewText(R.id.wcs_weekday, "WISDOMAPP")
        views.setViewVisibility(R.id.wcs_ev1_block, View.GONE)
        views.setViewVisibility(R.id.wcs_ev2_block, View.GONE)
        views.setViewVisibility(R.id.wcs_tomorrow_label, View.GONE)
        views.setViewVisibility(R.id.wcs_tomorrow_block, View.GONE)
        views.setViewVisibility(R.id.wcs_empty, View.VISIBLE)
        views.setTextViewText(R.id.wcs_empty, "Toque para abrir")
        return views
    }

    private fun buildSmallWidget(
        context: Context,
        widgetData: android.content.SharedPreferences,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_calendar_small)
        val jsonRaw = widgetData.getString(ControleTotalWidgetProvider.JSON_KEY, null)
        val data = WidgetJsonHelper.parseCompact(jsonRaw) ?: return buildFailSafe(context)

        views.setTextViewText(R.id.wcs_day_num, data.dayNum)
        views.setTextViewText(R.id.wcs_weekday, data.weekday)
        views.setTextColor(
            R.id.wcs_day_num,
            WidgetJsonHelper.parseColorSafe(data.dayColor, "#FFFF8A50"),
        )

        bindEventBlock(
            views,
            blockId = R.id.wcs_ev1_block,
            barId = R.id.wcs_ev1_bar,
            syId = R.id.wcs_ev1_sy,
            titleId = R.id.wcs_ev1_title,
            timeId = R.id.wcs_ev1_time,
            event = data.todayEvents.getOrNull(0),
        )
        bindEventBlock(
            views,
            blockId = R.id.wcs_ev2_block,
            barId = R.id.wcs_ev2_bar,
            syId = R.id.wcs_ev2_sy,
            titleId = R.id.wcs_ev2_title,
            timeId = R.id.wcs_ev2_time,
            event = data.todayEvents.getOrNull(1),
        )

        val tomorrow = data.tomorrowEvent
        if (tomorrow != null) {
            views.setViewVisibility(R.id.wcs_tomorrow_label, View.VISIBLE)
            views.setViewVisibility(R.id.wcs_tomorrow_block, View.VISIBLE)
            views.setTextViewText(R.id.wcs_tomorrow_sy, tomorrow.symbol.ifEmpty { "📅" })
            views.setTextViewText(R.id.wcs_tomorrow_title, tomorrow.title)
            views.setInt(
                R.id.wcs_tomorrow_bar,
                "setBackgroundColor",
                WidgetJsonHelper.parseColorSafe(tomorrow.barColor, "#FF2563EB"),
            )
            views.setInt(
                R.id.wcs_tomorrow_block,
                "setBackgroundColor",
                WidgetJsonHelper.pillBackgroundColor(tomorrow.barColor),
            )
        } else {
            views.setViewVisibility(R.id.wcs_tomorrow_label, View.GONE)
            views.setViewVisibility(R.id.wcs_tomorrow_block, View.GONE)
        }

        if (data.emptyText != null) {
            views.setViewVisibility(R.id.wcs_empty, View.VISIBLE)
            views.setTextViewText(R.id.wcs_empty, data.emptyText)
        } else {
            views.setViewVisibility(R.id.wcs_empty, View.GONE)
        }

        // Finance blocks
        bindFinanceBlock(
            views,
            blockId = R.id.wcs_fi1_block,
            barId = R.id.wcs_fi1_bar,
            syId = R.id.wcs_fi1_sy,
            textId = R.id.wcs_fi1_text,
            item = data.financeItems.getOrNull(0),
        )
        bindFinanceBlock(
            views,
            blockId = R.id.wcs_fi2_block,
            barId = R.id.wcs_fi2_bar,
            syId = R.id.wcs_fi2_sy,
            textId = R.id.wcs_fi2_text,
            item = data.financeItems.getOrNull(1),
        )

        return views
    }

    private fun bindFinanceBlock(
        views: RemoteViews,
        blockId: Int,
        barId: Int,
        syId: Int,
        textId: Int,
        item: WidgetJsonHelper.CompactFinanceItem?,
    ) {
        if (item == null) {
            views.setViewVisibility(blockId, View.GONE)
            return
        }
        views.setViewVisibility(blockId, View.VISIBLE)
        views.setTextViewText(syId, item.symbol.ifEmpty { "💳" })
        views.setTextViewText(textId, item.text)
        views.setInt(
            barId,
            "setBackgroundColor",
            WidgetJsonHelper.parseColorSafe(item.barColor, "#FFFF5252"),
        )
    }

    private fun bindEventBlock(
        views: RemoteViews,
        blockId: Int,
        barId: Int,
        syId: Int,
        titleId: Int,
        timeId: Int,
        event: WidgetJsonHelper.CompactEvent?,
    ) {
        if (event == null) {
            views.setViewVisibility(blockId, View.GONE)
            return
        }
        views.setViewVisibility(blockId, View.VISIBLE)
        views.setTextViewText(syId, event.symbol.ifEmpty { "🚔" })
        views.setTextViewText(titleId, event.title)
        views.setInt(
            barId,
            "setBackgroundColor",
            WidgetJsonHelper.parseColorSafe(event.barColor, "#FF2563EB"),
        )
        views.setInt(
            blockId,
            "setBackgroundColor",
            WidgetJsonHelper.pillBackgroundColor(event.barColor),
        )
        if (event.time.isNotBlank()) {
            views.setViewVisibility(timeId, View.VISIBLE)
            views.setTextViewText(timeId, event.time)
        } else {
            views.setViewVisibility(timeId, View.GONE)
        }
    }

    private fun attachClickOpenApp(
        context: Context,
        views: RemoteViews,
        widgetData: android.content.SharedPreferences,
    ) {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        var module = widgetData.getInt("widget_open_module", -1)
        if (module !in 0..9) {
            module = widgetData.getInt("flutter.home_start_mod_idx_v1", 0)
        }
        if (module !in 0..9) module = ControleTotalWidgetProvider.OPEN_MODULE_SCALES
        val launch = Intent(context, MainActivity::class.java).apply {
            setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(ControleTotalWidgetProvider.EXTRA_OPEN_MODULE, module)
        }
        val pi = PendingIntent.getActivity(context, module + 100, launch, flags)
        views.setOnClickPendingIntent(R.id.widget_root, pi)
    }
}

