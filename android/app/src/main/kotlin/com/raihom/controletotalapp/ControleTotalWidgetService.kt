package com.wisdomapp.app

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject

/// Lista do widget — lê JSON v2 mastigado pelo Flutter (só strings, zero lógica).
class ControleTotalWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return ControleTotalWidgetFactory(applicationContext, intent)
    }
}

class ControleTotalWidgetFactory(
    private val context: Context,
    intent: Intent,
) : RemoteViewsService.RemoteViewsFactory {

    private val items = mutableListOf<WidgetRow>()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        items.clear()
        try {
            WidgetPayloadRollover.maybeRollover(context)
            items.addAll(loadRowsFromJson())
        } catch (_: Throwable) {
            items.clear()
        }
    }

    override fun onDestroy() {
        items.clear()
    }

    override fun getCount(): Int = items.size

    override fun getViewTypeCount(): Int = 4

    override fun getItemId(position: Int): Long {
        val item = items.getOrNull(position) ?: return position.toLong()
        return item.stableId
    }

    override fun hasStableIds(): Boolean = true

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewAt(position: Int): RemoteViews {
        return try {
            when (items[position].kind) {
                "h" -> buildDayHeader(items[position])
                "e" -> buildEvent(items[position])
                "f" -> buildFinance(items[position])
                else -> buildText(items[position])
            }
        } catch (_: Throwable) {
            buildText(WidgetRow(kind = "x", text = "Sem compromissos para hoje"))
        }
    }

    private fun buildDayHeader(row: WidgetRow): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_item_day_header)
        views.setTextViewText(R.id.witem_day_num, row.dayNum)
        views.setTextViewText(R.id.witem_weekday, row.weekday)
        views.setTextColor(R.id.witem_day_num, parseColorSafe(row.dayColor, "#FFFFFFFF"))
        return views
    }

    private fun buildEvent(row: WidgetRow): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_item_event)
        views.setTextViewText(R.id.witem_symbol, row.symbol.ifEmpty { "🚔" })
        views.setTextViewText(R.id.witem_title, row.title.ifEmpty { "Evento" })
        views.setTextViewText(R.id.witem_time, row.time)
        views.setInt(R.id.witem_event_bar, "setBackgroundColor", parseColorSafe(row.barColor, "#FF00BCD4"))
        return views
    }

    private fun buildFinance(row: WidgetRow): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_item_finance)
        views.setTextViewText(R.id.witem_finance_symbol, row.symbol.ifEmpty { "💳" })
        views.setTextViewText(R.id.witem_finance_text, row.text)
        views.setInt(R.id.witem_finance_bar, "setBackgroundColor", parseColorSafe(row.barColor, "#FFFF5252"))
        return views
    }

    private fun buildText(row: WidgetRow): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_item_text)
        views.setTextViewText(R.id.witem_text, row.text.ifEmpty { "Sem compromissos para hoje" })
        return views
    }

    private fun loadRowsFromJson(): List<WidgetRow> {
        val out = mutableListOf<WidgetRow>()
        try {
            val prefs = HomeWidgetPlugin.getData(context)
            val raw = prefs.getString(ControleTotalWidgetProvider.JSON_KEY, null)
            if (raw.isNullOrBlank()) return out

            val root = JSONObject(raw)
            val rows = root.optJSONArray("rows")
            if (rows != null) {
                for (i in 0 until rows.length()) {
                    parseNativeRow(rows.optJSONObject(i))?.let { out.add(it) }
                }
                return out
            }

            // Fallback legado v1
            val legacy = root.optJSONArray("listItems") ?: return out
            for (i in 0 until legacy.length()) {
                parseLegacyRow(legacy.optJSONObject(i))?.let { out.add(it) }
            }
        } catch (_: Throwable) {
        }
        return out
    }

    private fun parseNativeRow(obj: JSONObject?): WidgetRow? {
        if (obj == null) return null
        val kind = obj.optString("k", "")
        if (kind.isEmpty()) return null
        return WidgetRow(
            kind = kind,
            dayNum = obj.optString("dn", ""),
            weekday = obj.optString("wd", ""),
            dayColor = obj.optString("dc", "#FFFFFFFF"),
            symbol = obj.optString("sy", ""),
            title = obj.optString("ti", ""),
            time = obj.optString("tm", ""),
            barColor = obj.optString("bc", "#FF00BCD4"),
            text = obj.optString("tx", ""),
        )
    }

    private fun parseLegacyRow(obj: JSONObject?): WidgetRow? {
        if (obj == null) return null
        return when (obj.optString("itemType", "")) {
            "day_header" -> WidgetRow(
                kind = "h",
                dayNum = obj.optInt("dayNum", 0).toString(),
                weekday = obj.optString("weekday", ""),
                dayColor = if (obj.optBoolean("isToday", false)) "#FFFF8A50" else "#FFFFFFFF",
            )
            "event" -> WidgetRow(
                kind = "e",
                symbol = obj.optString("symbol", "🚔"),
                title = obj.optString("title", "Evento"),
                time = obj.optString("time", ""),
                barColor = accentToColor(obj.optString("accent", "")),
            )
            "finance" -> WidgetRow(
                kind = "f",
                symbol = obj.optString("symbol", "💳"),
                text = obj.optString("text", ""),
            )
            "empty", "more" -> WidgetRow(
                kind = "x",
                text = obj.optString("text", ""),
            )
            else -> null
        }
    }

    private fun accentToColor(hexRaw: String): String {
        val hex = hexRaw.trim()
        if (hex.length == 8) return "#$hex"
        return "#FF00BCD4"
    }

    private fun parseColorSafe(raw: String, fallback: String): Int {
        return try {
            Color.parseColor(raw.ifBlank { fallback })
        } catch (_: Throwable) {
            try {
                Color.parseColor(fallback)
            } catch (_: Throwable) {
                Color.WHITE
            }
        }
    }

    private data class WidgetRow(
        val kind: String,
        val dayNum: String = "",
        val weekday: String = "",
        val dayColor: String = "#FFFFFFFF",
        val symbol: String = "",
        val title: String = "",
        val time: String = "",
        val barColor: String = "#FF00BCD4",
        val text: String = "",
    ) {
        val stableId: Long
            get() = "$kind|$dayNum|$weekday|$title|$time|$text".hashCode().toLong()
    }
}

