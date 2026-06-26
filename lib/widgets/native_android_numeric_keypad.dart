import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native_numeric_keypad_bridge.dart';

/// Host do [NumericKeypadView] Kotlin (Platform View). Só Android; outros alvos = shrink.
class NativeAndroidNumericKeypad extends StatefulWidget {
  const NativeAndroidNumericKeypad({
    super.key,
    required this.instanceId,
    required this.onEvent,
  });

  final int instanceId;
  final void Function(Map<String, dynamic> event) onEvent;

  @override
  State<NativeAndroidNumericKeypad> createState() =>
      _NativeAndroidNumericKeypadState();
}

class _NativeAndroidNumericKeypadState
    extends State<NativeAndroidNumericKeypad> {
  @override
  void initState() {
    super.initState();
    NativeNumericKeypadBridge.register(widget.instanceId, widget.onEvent);
  }

  @override
  void didUpdateWidget(covariant NativeAndroidNumericKeypad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.instanceId != widget.instanceId) {
      NativeNumericKeypadBridge.unregister(oldWidget.instanceId);
      NativeNumericKeypadBridge.register(widget.instanceId, widget.onEvent);
    } else if (oldWidget.onEvent != widget.onEvent) {
      NativeNumericKeypadBridge.register(widget.instanceId, widget.onEvent);
    }
  }

  @override
  void dispose() {
    NativeNumericKeypadBridge.unregister(widget.instanceId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 288,
        width: double.infinity,
        child: AndroidView(
          viewType: 'com.raihom.controletotalapp/numeric_keypad',
          creationParams: <String, dynamic>{
            'instanceId': widget.instanceId,
          },
          creationParamsCodec: const StandardMessageCodec(),
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
          },
        ),
      ),
    );
  }
}
