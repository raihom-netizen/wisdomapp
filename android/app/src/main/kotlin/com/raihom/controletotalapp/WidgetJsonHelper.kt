package com.wisdomapp.app

import org.json.JSONObject

/// Parseia JSON v2 do Flutter para o widget compacto 2×2 (hoje + amanhã).
object WidgetJsonHelper {

    data class CompactEvent(
        val symbol: String,
        val title: String,
        val time: String,
        val barColor: String,
    )

    data class CompactFinanceItem(
        val symbol: String,
        val text: String,
        val barColor: String,
    )

    data class CompactWidgetData(
        val dayNum: String,
        val weekday: String,
        val dayColor: String,
        val todayEvents: List<CompactEvent>,
        val tomorrowEvent: CompactEvent?,
        val emptyText: String?,
        val financeItems: List<CompactFinanceItem>,
    )

    data class FutureSection(
        val header: String,
        val events: List<CompactEvent>,
    )

    data class MediumWidgetData(
        val todayWeekday: String,
        val todayDayNum: String,
        val todayDayColor: String,
        val todayEvents: List<CompactEvent>,
        val futureSections: List<FutureSection>,
        val financeItems: List<CompactFinanceItem>,
    )

    fun parseCompact(jsonRaw: String?): CompactWidgetData? {
        if (jsonRaw.isNullOrBlank()) return null
        return try {
            val root = JSONObject(jsonRaw)
            val rows = root.optJSONArray("rows") ?: return null

            var dayIndex = -1
            var todayHeader: JSONObject? = null
            val todayEvents = mutableListOf<CompactEvent>()
            val tomorrowEvents = mutableListOf<CompactEvent>()
            val financeItems = mutableListOf<CompactFinanceItem>()
            var emptyText: String? = null

            for (i in 0 until rows.length()) {
                val row = rows.optJSONObject(i) ?: continue
                when (row.optString("k", "")) {
                    "h" -> {
                        dayIndex += 1
                        if (dayIndex == 0) todayHeader = row
                    }
                    "e" -> {
                        val ev = parseEvent(row)
                        when (dayIndex) {
                            0 -> if (todayEvents.size < 2) todayEvents.add(ev)
                            1 -> if (tomorrowEvents.size < 1) tomorrowEvents.add(ev)
                        }
                    }
                    "f" -> {
                        financeItems.add(parseFinance(row))
                    }
                    "x", "m" -> {
                        if (dayIndex == 0 && todayEvents.isEmpty()) {
                            val tx = row.optString("tx", "").trim()
                            if (tx.isNotEmpty()) emptyText = tx
                        }
                    }
                }
            }

            val header = todayHeader
            val now = java.util.Calendar.getInstance()
            CompactWidgetData(
                dayNum = header?.optString("dn", "")?.ifBlank { "${now.get(java.util.Calendar.DAY_OF_MONTH)}" }
                    ?: "${now.get(java.util.Calendar.DAY_OF_MONTH)}",
                weekday = header?.optString("wd", "")?.ifBlank { "HOJE" } ?: "HOJE",
                dayColor = header?.optString("dc", "#FFFF8A50") ?: "#FFFF8A50",
                todayEvents = todayEvents,
                tomorrowEvent = tomorrowEvents.firstOrNull(),
                emptyText = if (todayEvents.isEmpty()) {
                    emptyText ?: "SEM COMPROMISSOS HOJE"
                } else null,
                financeItems = financeItems.take(2),
            )
        } catch (_: Throwable) {
            null
        }
    }

    fun parseMedium(jsonRaw: String?): MediumWidgetData? {
        if (jsonRaw.isNullOrBlank()) return null
        return try {
            val root = JSONObject(jsonRaw)
            val rows = root.optJSONArray("rows") ?: return null

            var dayIndex = -1
            var todayHeader: JSONObject? = null
            val todayEvents = mutableListOf<CompactEvent>()
            val futureSections = mutableListOf<FutureSection>()
            val financeItems = mutableListOf<CompactFinanceItem>()
            var currentHeader = ""
            val currentEvents = mutableListOf<CompactEvent>()

            fun flushFuture() {
                if (currentHeader.isNotBlank() && currentEvents.isNotEmpty()) {
                    futureSections.add(
                        FutureSection(
                            header = currentHeader,
                            events = currentEvents.toList(),
                        ),
                    )
                }
                currentEvents.clear()
            }

            for (i in 0 until rows.length()) {
                val row = rows.optJSONObject(i) ?: continue
                when (row.optString("k", "")) {
                    "h" -> {
                        dayIndex += 1
                        if (dayIndex == 0) {
                            todayHeader = row
                        } else if (futureSections.size < 3) {
                            flushFuture()
                            currentHeader = row.optString("wd", "").trim()
                        }
                    }
                    "e" -> {
                        val ev = parseEvent(row)
                        when {
                            dayIndex == 0 && todayEvents.size < 2 -> todayEvents.add(ev)
                            dayIndex > 0 && futureSections.size < 3 && currentEvents.size < 2 ->
                                currentEvents.add(ev)
                        }
                    }
                    "f" -> {
                        financeItems.add(parseFinance(row))
                    }
                }
            }
            flushFuture()

            val header = todayHeader
            val now = java.util.Calendar.getInstance()
            MediumWidgetData(
                todayWeekday = header?.optString("wd", "")?.ifBlank { "HOJE" } ?: "HOJE",
                todayDayNum = header?.optString("dn", "")?.ifBlank {
                    "${now.get(java.util.Calendar.DAY_OF_MONTH)}"
                } ?: "${now.get(java.util.Calendar.DAY_OF_MONTH)}",
                todayDayColor = header?.optString("dc", "#FFFFFFFF") ?: "#FFFFFFFF",
                todayEvents = todayEvents,
                futureSections = futureSections.take(3),
                financeItems = financeItems.take(2),
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun parseEvent(row: JSONObject): CompactEvent = CompactEvent(
        symbol = row.optString("sy", "🚔"),
        title = row.optString("ti", "Evento"),
        time = row.optString("tm", ""),
        barColor = row.optString("bc", "#FF2563EB"),
    )

    private fun parseFinance(row: JSONObject): CompactFinanceItem = CompactFinanceItem(
        symbol = row.optString("sy", "💳"),
        text = row.optString("tx", ""),
        barColor = row.optString("bc", "#FFFF5252"),
    )

    fun parseColorSafe(raw: String, fallback: String): Int {
        return try {
            android.graphics.Color.parseColor(raw.ifBlank { fallback })
        } catch (_: Throwable) {
            try {
                android.graphics.Color.parseColor(fallback)
            } catch (_: Throwable) {
                android.graphics.Color.WHITE
            }
        }
    }

    fun pillBackgroundColor(barColor: String): Int {
        val base = parseColorSafe(barColor, "#FF2563EB")
        return android.graphics.Color.argb(
            0x33,
            android.graphics.Color.red(base),
            android.graphics.Color.green(base),
            android.graphics.Color.blue(base),
        )
    }
}

