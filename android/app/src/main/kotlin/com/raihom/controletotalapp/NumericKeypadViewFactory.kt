package com.wisdomapp.app

import android.content.Context
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class NumericKeypadViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val instanceId = (params?.get("instanceId") as? Number)?.toInt() ?: viewId
        val view = NumericKeypadView(context, messenger, instanceId)
        return object : PlatformView {
            override fun getView(): View = view

            override fun dispose() {}
        }
    }
}
