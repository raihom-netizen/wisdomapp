package com.wisdomapp.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

// Widget da tela inicial: **apenas Escalas** (calendário do mês). Toque abre o módulo Escalas.
class ControleTotalWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = try {
                buildScales(context, widgetData)
            } catch (_: Throwable) {
                // Blindagem: se algo der errado ao montar o RemoteViews,
                // renderiza um layout mínimo válido para evitar o erro
                // "Não é possível carregar o widget" no launcher (MIUI/Xiaomi).
                RemoteViews(context.packageName, R.layout.controle_total_widget)
            }
            try {
                attachClickOpenScales(context, views)
            } catch (_: Throwable) {
                // Ignora: clique é desejável mas não pode impedir o widget de aparecer.
            }
            try {
                appWidgetManager.updateAppWidget(widgetId, views)
            } catch (_: Throwable) {
                // Última defesa: nunca propagar exceção para o sistema.
            }
        }
    }

    private fun attachClickOpenScales(context: Context, views: RemoteViews) {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val launch = Intent(context, MainActivity::class.java).apply {
            setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_OPEN_MODULE, OPEN_MODULE_SCALES)
        }
        val pi = PendingIntent.getActivity(context, OPEN_MODULE_SCALES, launch, flags)
        views.setOnClickPendingIntent(R.id.widget_root, pi)
    }

    private fun buildScales(
        context: Context,
        widgetData: android.content.SharedPreferences,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_scales_calendar)
        val title = widgetData.getString("widget_cal_title", "Escalas") ?: "Escalas"
        views.setTextViewText(R.id.widget_scales_month, title)

        val payload = widgetData.getString("widget_cal_payload", null)
        val cells = if (payload.isNullOrBlank()) {
            emptyList()
        } else {
            payload.split(";")
        }

        for (i in 0 until 42) {
            val id = context.resources.getIdentifier("wcal_$i", "id", context.packageName)
            if (id == 0) continue
            val raw = cells.getOrNull(i) ?: ""
            val parts = raw.split(",")
            val day = parts.getOrNull(0)?.toIntOrNull() ?: 0
            val bgHex = parts.getOrNull(2) ?: "FFF1F5F9"
            val fgHex = parts.getOrNull(3) ?: "FF1A1C1E"
            val dots = parts.getOrNull(4)?.toIntOrNull() ?: 0

            if (day <= 0) {
                views.setTextViewText(id, "")
                views.setInt(id, "setBackgroundColor", parseArgbHex("FFF8FAFC"))
                continue
            }

            val fg = parseArgbHex(fgHex)
            val bg = parseArgbHex(bgHex)
            val dotStr = when {
                dots > 1 -> "\n" + "•".repeat(dots.coerceAtMost(3))
                else -> ""
            }
            views.setTextViewText(id, "$day$dotStr")
            views.setTextColor(id, fg)
            views.setInt(id, "setBackgroundColor", bg)
        }

        val dateStr = widgetData.getString("next_scale_date", "") ?: ""
        val label = widgetData.getString("next_scale_label", "") ?: ""
        val timeStr = widgetData.getString("next_scale_time", "") ?: ""
        val hint = when {
            dateStr.isNotEmpty() && timeStr.isNotEmpty() ->
                "Próximo: $label • $dateStr $timeStr — toque para Escalas"
            dateStr.isNotEmpty() ->
                "Próximo: $label • $dateStr — toque para Escalas"
            label.isNotEmpty() && label != "Nenhum plantão em breve" ->
                "Próximo: $label — toque para Escalas"
            else ->
                "Toque para abrir Escalas"
        }
        views.setTextViewText(R.id.widget_scales_hint, hint)
        return views
    }

    private fun parseArgbHex(hexRaw: String): Int {
        val hex = hexRaw.trim().lowercase()
        if (hex.length != 8) return Color.parseColor("#F1F5F9")
        return try {
            java.lang.Integer.parseUnsignedInt(hex, 16)
        } catch (_: Exception) {
            Color.parseColor("#F1F5F9")
        }
    }

    companion object {
        const val EXTRA_OPEN_MODULE = "ct_open_module"
        const val OPEN_MODULE_SCALES = 3
    }
}
