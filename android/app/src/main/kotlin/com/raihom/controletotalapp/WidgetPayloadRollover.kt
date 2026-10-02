package com.wisdomapp.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

/**
 * Reconstrói as linhas do widget quando o dia civil mudou (meia-noite) — app fechado.
 * Usa o array [events] gravado pelo Flutter; mantém financeiro e marca do payload.
 */
object WidgetPayloadRollover {

    private const val HORIZON_DAYS = 5
    private const val MAX_EVENTS_TODAY = 8
    private const val MAX_EVENTS_FUTURE = 6
    private const val TITLE_MAX_LEN = 42
  private const val PREFS = "HomeWidgetPreferences"

    private val WEEKDAY_NAMES = arrayOf(
        "",
        "SEGUNDA-FEIRA",
        "TERÇA-FEIRA",
        "QUARTA-FEIRA",
        "QUINTA-FEIRA",
        "SEXTA-FEIRA",
        "SÁBADO",
        "DOMINGO",
    )

    private val MONTH_ABBR = arrayOf(
        "JAN", "FEV", "MAR", "ABR", "MAI", "JUN",
        "JUL", "AGO", "SET", "OUT", "NOV", "DEZ",
    )

    fun maybeRollover(context: Context): Boolean {
        return try {
            val prefs = context.applicationContext.getSharedPreferences(
                PREFS,
                Context.MODE_PRIVATE,
            )
            val key = ControleTotalWidgetProvider.JSON_KEY
            val raw = prefs.getString(key, null) ?: return false
            val updated = maybeRolloverJson(raw, System.currentTimeMillis()) ?: return false
            prefs.edit().putString(key, updated).commit()
        } catch (_: Throwable) {
            false
        }
    }

    fun maybeRolloverJson(raw: String, nowMs: Long = System.currentTimeMillis()): String? {
        return try {
            val root = JSONObject(raw)
            val events = root.optJSONArray("events") ?: return null
            if (events.length() == 0) return null

            val todayStartMs = startOfDayMs(nowMs)
            val horizonStart = root.optLong("horizonStartMs", 0L)
            val hasExpiredVisible = hasExpiredWidgetEvents(events, nowMs)
            if (horizonStart == todayStartMs && !hasExpiredVisible) return null

            val financeRows = extractFinanceRows(root.optJSONArray("rows"))
            val rebuilt = rebuildPayload(root, events, todayStartMs, nowMs, financeRows)
            rebuilt.toString()
        } catch (_: Throwable) {
            null
        }
    }

    private fun hasExpiredWidgetEvents(eventsArr: JSONArray, nowMs: Long): Boolean {
        for (i in 0 until eventsArr.length()) {
            val ev = eventsArr.optJSONObject(i) ?: continue
            val until = ev.optLong("visibleUntilMs", 0L)
            if (until > 0L && nowMs >= until) return true
        }
        return false
    }

    private fun extractFinanceRows(rows: JSONArray?): List<JSONObject> {
        val out = mutableListOf<JSONObject>()
        if (rows == null) return out
        for (i in 0 until rows.length()) {
            val row = rows.optJSONObject(i) ?: continue
            if (row.optString("k", "") == "f") out.add(row)
        }
        return out
    }

    private fun rebuildPayload(
        root: JSONObject,
        eventsArr: JSONArray,
        todayStartMs: Long,
        nowMs: Long,
        financeRows: List<JSONObject>,
    ): JSONObject {
        val events = mutableListOf<JSONObject>()
        for (i in 0 until eventsArr.length()) {
            eventsArr.optJSONObject(i)?.let { events.add(it) }
        }

        events.removeAll { ev ->
            val dayMs = ev.optLong("dayMs", 0L)
            if (dayMs < todayStartMs) return@removeAll true
            val until = ev.optLong("visibleUntilMs", 0L)
            if (until > 0L && nowMs >= until) return@removeAll true
            false
        }
        events.sortBy { it.optLong("sortMs", 0L) }

        val rows = JSONArray()
        var hasAnyEvent = false

        for (i in 0 until HORIZON_DAYS) {
            val dayMs = todayStartMs + i * 86_400_000L
            val dayKey = dayOnlyMs(dayMs)
            val isToday = i == 0
            val cal = calendarFromMs(dayMs)

            rows.put(
                JSONObject().apply {
                    put("k", "h")
                    put("dn", "${cal.get(Calendar.DAY_OF_MONTH)}")
                    put("wd", headerLabel(cal, isToday))
                    put("ws", weekdayShort(cal))
                    put("td", if (isToday) "1" else "0")
                    put("dc", if (isToday) "#FFFF8A50" else "#FFFFFFFF")
                },
            )

            val dayEvents = events.filter { ev ->
                dayOnlyMs(ev.optLong("dayMs", 0L)) == dayKey
            }
            val max = if (isToday) MAX_EVENTS_TODAY else MAX_EVENTS_FUTURE
            val slice = dayEvents.take(max)
            val extra = dayEvents.size - slice.size

            if (slice.isEmpty()) {
                rows.put(
                    JSONObject().apply {
                        put("k", "x")
                        put(
                            "tx",
                            if (isToday) "SEM COMPROMISSOS PARA HOJE"
                            else "SEM COMPROMISSOS",
                        )
                    },
                )
            } else {
                for (ev in slice) {
                    hasAnyEvent = true
                    val type = ev.optString("type", "scale")
                    val title = ev.optString("title", "EVENTO")
                    val accent = ev.optString("accentHex", "").trim()
                    val symbol = ev.optString("symbol", "🚔")
                    rows.put(
                        JSONObject().apply {
                            put("k", "e")
                            put("sy", symbol)
                            put("ti", truncate(title, TITLE_MAX_LEN).uppercase(Locale.getDefault()))
                            put("tm", ev.optString("timeRange", "").uppercase(Locale.getDefault()))
                            put(
                                "bc",
                                if (accent.isNotEmpty()) {
                                    if (accent.startsWith("#")) accent else "#$accent"
                                } else {
                                    defaultBarColor(isToday)
                                },
                            )
                            put("ag", type)
                        },
                    )
                }
                if (extra > 0) {
                    rows.put(
                        JSONObject().apply {
                            put("k", "m")
                            put("tx", "+$extra EVENTO(S)")
                        },
                    )
                }
            }
        }

        for (fr in financeRows) { rows.put(fr) }

        val financeRaw = root.optString("financeRaw", "")
        val hasFinance = financeRows.isNotEmpty() || financeRaw.isNotBlank()
        val hint = if (!hasAnyEvent && !hasFinance) {
            "SEM COMPROMISSOS PARA HOJE — TOQUE PARA ABRIR"
        } else {
            "TOQUE PARA ABRIR O WISDOMAPP"
        }

        return JSONObject().apply {
            put("v", root.optString("v", "2"))
            put("rev", nowMs)
            put("horizonStartMs", todayStartMs)
            put("brand", root.optString("brand", "WISDOMAPP").uppercase(Locale.getDefault()))
            put("hint", hint)
            put("updated", formatUpdatedAt(nowMs))
            put("events", JSONArray().apply { events.forEach { put(it) } })
            put("rows", rows)
            if (financeRaw.isNotBlank()) put("financeRaw", financeRaw)
        }
    }

    private fun headerLabel(cal: Calendar, isToday: Boolean): String {
        val mapped = weekdayIndex(cal)
        if (mapped !in 1..7) return ""
        val wd = WEEKDAY_NAMES[mapped]
        if (isToday) return wd
        val month = MONTH_ABBR[cal.get(Calendar.MONTH)]
        return "$wd, ${cal.get(Calendar.DAY_OF_MONTH)} DE $month."
    }

    private fun weekdayShort(cal: Calendar): String {
        val label = headerLabel(cal, isToday = true)
        val part = label.split("-").firstOrNull()?.trim().orEmpty()
        return if (part.length <= 3) part else part.substring(0, 3)
    }

    private fun defaultBarColor(isToday: Boolean): String =
        if (isToday) "#FF00BCD4" else "#FF2563EB"

    private fun truncate(raw: String, maxLen: Int): String {
        val s = raw.trim()
        if (s.length <= maxLen) return s
        if (maxLen <= 1) return s.substring(0, maxLen)
        return s.substring(0, maxLen - 1) + "…"
    }

    private fun formatUpdatedAt(nowMs: Long): String {
        val cal = calendarFromMs(nowMs)
        val dd = cal.get(Calendar.DAY_OF_MONTH).toString().padStart(2, '0')
        val mm = (cal.get(Calendar.MONTH) + 1).toString().padStart(2, '0')
        val hh = cal.get(Calendar.HOUR_OF_DAY).toString().padStart(2, '0')
        val mi = cal.get(Calendar.MINUTE).toString().padStart(2, '0')
        return "$dd/$mm $hh:$mi"
    }

    private fun startOfDayMs(ms: Long): Long {
        val cal = calendarFromMs(ms)
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    private fun dayOnlyMs(ms: Long): String = startOfDayMs(ms).toString()

    private fun calendarFromMs(ms: Long): Calendar =
        Calendar.getInstance().apply { timeInMillis = ms }

    private fun weekdayIndex(cal: Calendar): Int = when (cal.get(Calendar.DAY_OF_WEEK)) {
        Calendar.MONDAY -> 1
        Calendar.TUESDAY -> 2
        Calendar.WEDNESDAY -> 3
        Calendar.THURSDAY -> 4
        Calendar.FRIDAY -> 5
        Calendar.SATURDAY -> 6
        Calendar.SUNDAY -> 7
        else -> 0
    }
}

