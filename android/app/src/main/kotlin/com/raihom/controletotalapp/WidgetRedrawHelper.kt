package com.wisdomapp.app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/// Redesenho imediato dos 3 widgets após Flutter gravar JSON (lista + small + medium).
object WidgetRedrawHelper {

    private val providerClasses = listOf(
        ControleTotalWidgetProvider::class.java,
        ControleTotalWidgetSmallProvider::class.java,
        ControleTotalWidgetMediumProvider::class.java,
    )

    fun requestAllWidgetsRedraw(context: Context) {
        val appContext = context.applicationContext
        val manager = AppWidgetManager.getInstance(appContext)
        for (clazz in providerClasses) {
            try {
                val component = ComponentName(appContext, clazz)
                val ids = manager.getAppWidgetIds(component)
                if (ids.isEmpty()) continue
                val update = Intent(appContext, clazz).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                appContext.sendBroadcast(update)
                // Lista (RemoteViewsService) precisa de notify explícito por widget id.
                if (clazz == ControleTotalWidgetProvider::class.java) {
                    for (id in ids) {
                        try {
                            manager.notifyAppWidgetViewDataChanged(
                                id,
                                R.id.widget_events_list,
                            )
                        } catch (_: Throwable) {
                        }
                    }
                }
            } catch (_: Throwable) {
            }
        }
    }
}

