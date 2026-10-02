package com.wisdomapp.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

/// Widget médio 4×2 — hoje à esquerda + próximos dias à direita (estilo referência iOS).
class ControleTotalWidgetMediumProvider : es.antonborri.home_widget.HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences,
    ) {
        WidgetPayloadRollover.maybeRollover(context)
        appWidgetIds.forEach { widgetId ->
            val views = try {
                buildMediumWidget(context, widgetData)
            } catch (_: Throwable) {
                buildFailSafeMedium(context)
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

    private fun buildMediumWidget(
        context: Context,
        widgetData: android.content.SharedPreferences,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_calendar_medium)
        val jsonRaw = widgetData.getString(ControleTotalWidgetProvider.JSON_KEY, null)
        val data = WidgetJsonHelper.parseMedium(jsonRaw) ?: return buildFailSafeMedium(context)

        views.setTextViewText(R.id.wcm_weekday, data.todayWeekday)
        views.setTextViewText(R.id.wcm_day_num, data.todayDayNum)
        views.setTextColor(
            R.id.wcm_day_num,
            WidgetJsonHelper.parseColorSafe(data.todayDayColor, "#FFFFFFFF"),
        )

        bindMediumEvent(
            views,
            blockId = R.id.wcm_today_ev1_block,
            barId = R.id.wcm_today_ev1_bar,
            syId = R.id.wcm_today_ev1_sy,
            titleId = R.id.wcm_today_ev1_title,
            timeId = R.id.wcm_today_ev1_time,
            event = data.todayEvents.getOrNull(0),
            showTime = true,
        )
        bindMediumEvent(
            views,
            blockId = R.id.wcm_today_ev2_block,
            barId = R.id.wcm_today_ev2_bar,
            syId = R.id.wcm_today_ev2_sy,
            titleId = R.id.wcm_today_ev2_title,
            timeId = R.id.wcm_today_ev2_time,
            event = data.todayEvents.getOrNull(1),
            showTime = true,
        )

        if (data.todayEvents.isEmpty()) {
            views.setViewVisibility(R.id.wcm_today_empty, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.wcm_today_empty, View.GONE)
        }

        bindFutureSection(
            views,
            section = data.futureSections.getOrNull(0),
            headerId = R.id.wcm_f1_header,
            ev1Block = R.id.wcm_f1_ev1_block,
            ev1Bar = R.id.wcm_f1_ev1_bar,
            ev1Sy = R.id.wcm_f1_ev1_sy,
            ev1Title = R.id.wcm_f1_ev1_title,
            ev2Block = R.id.wcm_f1_ev2_block,
            ev2Bar = R.id.wcm_f1_ev2_bar,
            ev2Sy = R.id.wcm_f1_ev2_sy,
            ev2Title = R.id.wcm_f1_ev2_title,
        )
        bindFutureSection(
            views,
            section = data.futureSections.getOrNull(1),
            headerId = R.id.wcm_f2_header,
            ev1Block = R.id.wcm_f2_ev1_block,
            ev1Bar = R.id.wcm_f2_ev1_bar,
            ev1Sy = R.id.wcm_f2_ev1_sy,
            ev1Title = R.id.wcm_f2_ev1_title,
            ev2Block = null,
            ev2Bar = null,
            ev2Sy = null,
            ev2Title = null,
        )
        bindFutureSection(
            views,
            section = data.futureSections.getOrNull(2),
            headerId = R.id.wcm_f3_header,
            ev1Block = R.id.wcm_f3_ev1_block,
            ev1Bar = R.id.wcm_f3_ev1_bar,
            ev1Sy = R.id.wcm_f3_ev1_sy,
            ev1Title = R.id.wcm_f3_ev1_title,
            ev2Block = null,
            ev2Bar = null,
            ev2Sy = null,
            ev2Title = null,
        )

        // Finance blocks
        bindMediumFinanceBlock(
            views,
            blockId = R.id.wcm_fi1_block,
            barId = R.id.wcm_fi1_bar,
            syId = R.id.wcm_fi1_sy,
            textId = R.id.wcm_fi1_text,
            item = data.financeItems.getOrNull(0),
        )
        bindMediumFinanceBlock(
            views,
            blockId = R.id.wcm_fi2_block,
            barId = R.id.wcm_fi2_bar,
            syId = R.id.wcm_fi2_sy,
            textId = R.id.wcm_fi2_text,
            item = data.financeItems.getOrNull(1),
        )

        return views
    }

    private fun bindMediumFinanceBlock(
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

    private fun bindFutureSection(
        views: RemoteViews,
        section: WidgetJsonHelper.FutureSection?,
        headerId: Int,
        ev1Block: Int,
        ev1Bar: Int,
        ev1Sy: Int,
        ev1Title: Int,
        ev2Block: Int?,
        ev2Bar: Int?,
        ev2Sy: Int?,
        ev2Title: Int?,
    ) {
        if (section == null) {
            views.setViewVisibility(headerId, View.GONE)
            views.setViewVisibility(ev1Block, View.GONE)
            ev2Block?.let { views.setViewVisibility(it, View.GONE) }
            return
        }
        views.setViewVisibility(headerId, View.VISIBLE)
        views.setTextViewText(headerId, section.header)
        bindMediumEvent(
            views,
            blockId = ev1Block,
            barId = ev1Bar,
            syId = ev1Sy,
            titleId = ev1Title,
            timeId = null,
            event = section.events.getOrNull(0),
            showTime = false,
        )
        if (ev2Block != null && ev2Bar != null && ev2Sy != null && ev2Title != null) {
            bindMediumEvent(
                views,
                blockId = ev2Block,
                barId = ev2Bar,
                syId = ev2Sy,
                titleId = ev2Title,
                timeId = null,
                event = section.events.getOrNull(1),
                showTime = false,
            )
        }
    }

    private fun bindMediumEvent(
        views: RemoteViews,
        blockId: Int,
        barId: Int,
        syId: Int,
        titleId: Int,
        timeId: Int?,
        event: WidgetJsonHelper.CompactEvent?,
        showTime: Boolean,
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
        if (timeId != null) {
            if (showTime && event.time.isNotBlank()) {
                views.setViewVisibility(timeId, View.VISIBLE)
                views.setTextViewText(timeId, event.time)
            } else {
                views.setViewVisibility(timeId, View.GONE)
            }
        }
    }

    private fun buildFailSafeMedium(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_calendar_medium)
        views.setTextViewText(R.id.wcm_weekday, "WISDOMAPP")
        views.setTextViewText(R.id.wcm_day_num, "?")
        views.setViewVisibility(R.id.wcm_today_empty, View.VISIBLE)
        views.setTextViewText(R.id.wcm_today_empty, "Toque para abrir")
        return views
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
        val pi = PendingIntent.getActivity(context, module + 200, launch, flags)
        views.setOnClickPendingIntent(R.id.widget_root, pi)
    }
}

