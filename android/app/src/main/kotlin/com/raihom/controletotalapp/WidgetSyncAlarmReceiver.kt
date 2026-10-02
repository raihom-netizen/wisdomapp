package com.wisdomapp.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

/**
 * Dispara atualização do widget às 00:00 e 12:00 (horário local).
 * Com o app fechado, redesenha o widget; ao abrir o app, o Flutter refaz a sync Firestore.
 */
class WidgetSyncAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED -> {
                WidgetSyncAlarmScheduler.scheduleNext(context)
            }
            ACTION_WIDGET_SYNC -> {
                WidgetPayloadRollover.maybeRollover(context)
                markSyncDue(context)
                requestWidgetRedraw(context)
                WidgetSyncAlarmScheduler.scheduleNext(context)
            }
        }
    }

    private fun markSyncDue(context: Context) {
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putLong(KEY_SYNC_DUE_MS, System.currentTimeMillis())
                .apply()
        } catch (_: Throwable) {
        }
    }

    private fun requestWidgetRedraw(context: Context) {
        WidgetRedrawHelper.requestAllWidgetsRedraw(context)
    }

    companion object {
        const val ACTION_WIDGET_SYNC = "com.wisdomapp.app.WIDGET_SYNC_ALARM"
        private const val PREFS = "controletotal_widget_sync"
        private const val KEY_SYNC_DUE_MS = "sync_due_ms"

        fun pendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, WidgetSyncAlarmReceiver::class.java).apply {
                action = ACTION_WIDGET_SYNC
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            return PendingIntent.getBroadcast(context, 0, intent, flags)
        }
    }
}

object WidgetSyncAlarmScheduler {

    private const val REQUEST_CODE = 73201
    private const val REQUEST_CODE_EXPIRY = 73202

    /**
     * Verifica se alarmes exatos são permitidos (Android 14+/API 34).
     * Em API < 34 sempre retorna true (não há restrição).
     */
    private fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return am.canScheduleExactAlarms()
    }

    /** Agenda o próximo alarme 00:00 ou 12:00. Fallback inexact em API 34+ sem permissão. */
    fun scheduleNext(context: Context) {
        try {
            val alarmManager =
                context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val triggerAt = nextTriggerMillis()
            val pi = WidgetSyncAlarmReceiver.pendingIntent(context)
            if (canScheduleExact(context)) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        pi,
                    )
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                }
            } else {
                // Fallback: alarme inexacto (pode atrasar até ~15 min no Doze).
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pi,
                )
            }
        } catch (_: Throwable) {
        }
    }

    fun cancel(context: Context) {
        try {
            val alarmManager =
                context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(WidgetSyncAlarmReceiver.pendingIntent(context))
        } catch (_: Throwable) {
        }
    }

    /** Próximo slot 00:00 ou 12:00 após agora. */
    private fun nextTriggerMillis(): Long {
        val now = Calendar.getInstance()
        val slots = intArrayOf(0, 12)
        for (dayOffset in 0..1) {
            for (hour in slots) {
                val cal = Calendar.getInstance().apply {
                    set(Calendar.HOUR_OF_DAY, hour)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                    add(Calendar.DAY_OF_YEAR, dayOffset)
                }
                if (cal.timeInMillis > now.timeInMillis) {
                    return cal.timeInMillis
                }
            }
        }
        return now.timeInMillis + 12 * 60 * 60 * 1000L
    }

    /** Alarme no fim da carência do plantão (fim + 2h) — limpa widget com app fechado. */
    fun scheduleExpiryAlarm(context: Context, expiryMs: Long) {
        if (expiryMs <= System.currentTimeMillis()) return
        try {
            val alarmManager =
                context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, WidgetSyncAlarmReceiver::class.java).apply {
                action = WidgetSyncAlarmReceiver.ACTION_WIDGET_SYNC
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val pi = PendingIntent.getBroadcast(context, REQUEST_CODE_EXPIRY, intent, flags)
            if (canScheduleExact(context)) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        expiryMs,
                        pi,
                    )
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, expiryMs, pi)
                }
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    expiryMs,
                    pi,
                )
            }
        } catch (_: Throwable) {
        }
    }
}

