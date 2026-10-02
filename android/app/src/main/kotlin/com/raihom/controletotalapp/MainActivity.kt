package com.wisdomapp.app

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

private const val launcherChannelName = "controletotal/launcher"
private const val widgetSyncChannelName = "controletotal/widget_sync"
private const val soundsChannelName = "controletotal/sons"
private const val widgetSyncPrefs = "controletotal_widget_sync"
private const val widgetSyncDueKey = "sync_due_ms"

/**
 * FlutterFragmentActivity é necessário para o diálogo de biometria/digital aparecer no Android.
 *
 * Android 15+ / targetSdk 35+: a Play Console recomenda [enableEdgeToEdge] para recuos (insets)
 * e compatibilidade com exibição ponta a ponta.
 */
class MainActivity : FlutterFragmentActivity() {
    /** MethodChannel exposto ao Flutter para abrir picker / configurações de teclado (IME). */
    private val keyboardChannelName = "controletotal/keyboard"

    /** Índice do módulo [HomeShell] vindo do widget (ou -1). */
    private var pendingOpenModuleIndex: Int = -1

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        captureOpenModuleFromIntent(intent)
        super.onCreate(savedInstanceState)
        try {
            WidgetSyncAlarmScheduler.scheduleNext(applicationContext)
        } catch (_: Throwable) {
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureOpenModuleFromIntent(intent)
    }

    private fun captureOpenModuleFromIntent(i: Intent?) {
        val v = i?.getIntExtra("ct_open_module", -1) ?: -1
        if (v >= 0) {
            pendingOpenModuleIndex = v
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.raihom.controletotalapp/numeric_keypad",
            NumericKeypadViewFactory(flutterEngine.dartExecutor.binaryMessenger),
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, keyboardChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Abre o seletor flutuante de teclado (mesmo da barra de notificações).
                    // Permite ao usuário trocar pra Gboard sem sair do app.
                    "showInputMethodPicker" -> {
                        try {
                            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                            imm.showInputMethodPicker()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PICKER_FAILED", e.message, null)
                        }
                    }
                    // Abre a tela de configurações de teclados do Android (fallback).
                    "openInputMethodSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SETTINGS_FAILED", e.message, null)
                        }
                    }
                    // Play Store / browser — Teclado Google (Gboard). Fallback HTTPS se não houver Play Store.
                    "openGboardPlayStore" -> {
                        try {
                            val marketUri =
                                Uri.parse("market://details?id=com.google.android.inputmethod.latin")
                            val intent = Intent(Intent.ACTION_VIEW, marketUri)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (_: Exception) {
                            try {
                                val webUri = Uri.parse(
                                    "https://play.google.com/store/apps/details?id=com.google.android.inputmethod.latin"
                                )
                                val intent = Intent(Intent.ACTION_VIEW, webUri)
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("STORE_FAILED", e2.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, launcherChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePendingModule" -> {
                        val v = pendingOpenModuleIndex
                        pendingOpenModuleIndex = -1
                        result.success(v)
                    }

                    else -> result.notImplemented()
                }
            }
        // Despertador: toque próprio (MP3/voz) nos avisos com o app fechado. O
        // sistema só toca som de canal que ELE consegue ler — por isso vai para
        // o MediaStore (mesma solução do Controle Total).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, soundsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "registrarSomProprio" -> {
                        val path = call.argument<String>("path")
                        val nome = call.argument<String>("nome") ?: "WisdomApp"
                        val anterior = call.argument<String>("anterior")
                        Thread {
                            val uri = try {
                                registrarSomProprio(path, nome, anterior)
                            } catch (_: Throwable) {
                                null
                            }
                            runOnUiThread { result.success(uri) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetSyncChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleAlarms" -> {
                        try {
                            WidgetSyncAlarmScheduler.scheduleNext(applicationContext)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SCHEDULE_FAILED", e.message, null)
                        }
                    }
                    "scheduleExpiryAlarm" -> {
                        try {
                            val expiryMs = (call.arguments as? Number)?.toLong() ?: 0L
                            if (expiryMs > 0L) {
                                WidgetSyncAlarmScheduler.scheduleExpiryAlarm(
                                    applicationContext,
                                    expiryMs,
                                )
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SCHEDULE_EXPIRY_FAILED", e.message, null)
                        }
                    }
                    "consumeSyncDue" -> {
                        try {
                            val prefs = applicationContext.getSharedPreferences(
                                widgetSyncPrefs,
                                Context.MODE_PRIVATE,
                            )
                            val dueMs = prefs.getLong(widgetSyncDueKey, 0L)
                            if (dueMs <= 0L) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            prefs.edit().remove(widgetSyncDueKey).apply()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CONSUME_FAILED", e.message, null)
                        }
                    }
                    "forceWidgetRedraw" -> {
                        try {
                            WidgetRedrawHelper.requestAllWidgetsRedraw(applicationContext)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("REDRAW_FAILED", e.message, null)
                        }
                    }
                    "persistWidgetJson" -> {
                        try {
                            @Suppress("UNCHECKED_CAST")
                            val args = call.arguments as? Map<String, Any?>
                            val json = args?.get("json") as? String
                            val key = (args?.get("key") as? String)
                                ?: ControleTotalWidgetProvider.JSON_KEY
                            if (json.isNullOrBlank()) {
                                result.error("BAD_ARGS", "json required", null)
                                return@setMethodCallHandler
                            }
                            val ok = applicationContext
                                .getSharedPreferences(
                                    "HomeWidgetPreferences",
                                    Context.MODE_PRIVATE,
                                )
                                .edit()
                                .putString(key, json)
                                .commit()
                            WidgetRedrawHelper.requestAllWidgetsRedraw(applicationContext)
                            result.success(ok)
                        } catch (e: Exception) {
                            result.error("PERSIST_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
    /**
     * Grava o WAV convertido em «Notifications/WisdomApp» (Android 10+, sem
     * permissão: é mídia do próprio app) e devolve o content:// para o canal.
     * Apaga o toque anterior da mesma categoria. Antes do Android 10 → null
     * (o aviso segue com o som padrão).
     */
    private fun registrarSomProprio(path: String?, nome: String, anterior: String?): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || path.isNullOrEmpty()) return null
        val arquivo = File(path)
        if (!arquivo.exists()) return null
        val resolver = contentResolver
        if (!anterior.isNullOrEmpty()) {
            try {
                resolver.delete(Uri.parse(anterior), null, null)
            } catch (_: Throwable) {
            }
        }
        val valores = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, arquivo.name)
            put(MediaStore.Audio.Media.TITLE, nome)
            put(MediaStore.Audio.Media.MIME_TYPE, "audio/wav")
            put(MediaStore.Audio.Media.RELATIVE_PATH, "${Environment.DIRECTORY_NOTIFICATIONS}/WisdomApp")
            put(MediaStore.Audio.Media.IS_NOTIFICATION, 1)
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, valores) ?: return null
        resolver.openOutputStream(uri)?.use { saida ->
            arquivo.inputStream().use { it.copyTo(saida) }
        } ?: run {
            resolver.delete(uri, null, null)
            return null
        }
        valores.clear()
        valores.put(MediaStore.Audio.Media.IS_PENDING, 0)
        resolver.update(uri, valores, null, null)
        return uri.toString()
    }
}
