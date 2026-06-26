package com.wisdomapp.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val launcherChannelName = "controletotal/launcher"

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
    }
}
