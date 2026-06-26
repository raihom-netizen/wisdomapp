package com.wisdomapp.app

import android.content.Context
import android.graphics.Typeface
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.widget.LinearLayout
import com.google.android.material.button.MaterialButton
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Teclado numérico nativo (sem IME): só envia eventos ao Flutter — latência mínima por toque.
 * Layout estilo calculadora; dígitos formam centavos como no [CurrencyInputFormatter] Dart.
 */
class NumericKeypadView(
    context: Context,
    messenger: BinaryMessenger,
    private val instanceId: Int,
) : LinearLayout(context) {

    private val channel = MethodChannel(messenger, "controletotal/native_numeric_keypad")

    init {
        orientation = VERTICAL
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
        setPadding(dp(6), dp(4), dp(6), dp(8))

        val rows = listOf(
            listOf("1", "2", "3"),
            listOf("4", "5", "6"),
            listOf("7", "8", "9"),
            listOf("C", "0", "⌫"),
        )

        for (row in rows) {
            val rowLayout = LinearLayout(context).apply {
                orientation = HORIZONTAL
                layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            }
            for (cell in row) {
                val btn = keyButton(cell) {
                    tapFeedback()
                    when (cell) {
                        "C" -> emit("clear", "")
                        "⌫" -> emit("backspace", "")
                        else -> emit("digit", cell)
                    }
                }
                rowLayout.addView(
                    btn,
                    LayoutParams(0, dp(52), 1f),
                )
            }
            addView(rowLayout)
        }

        val ok = MaterialButton(context).apply {
            text = "OK"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            typeface = Typeface.DEFAULT_BOLD
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, dp(50))
            setOnClickListener {
                tapFeedback()
                emit("done", "")
            }
        }
        addView(ok)
    }

    private fun dp(v: Int): Int =
        (v * resources.displayMetrics.density).toInt()

    private fun keyButton(label: String, onPress: () -> Unit): MaterialButton =
        MaterialButton(context).apply {
            text = label
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            minimumHeight = dp(52)
            minimumWidth = 0
            insetTop = 0
            insetBottom = 0
            gravity = Gravity.CENTER
            setOnClickListener { onPress() }
        }

    private fun tapFeedback() {
        performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
    }

    private fun emit(type: String, payload: String) {
        channel.invokeMethod(
            "event",
            mapOf(
                "instanceId" to instanceId,
                "type" to type,
                "payload" to payload,
            ),
        )
    }
}
