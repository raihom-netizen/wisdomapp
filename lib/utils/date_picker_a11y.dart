import 'package:flutter/material.dart' as material;

Future<DateTime?> showDatePicker({
  required material.BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? currentDate,
  material.DatePickerEntryMode initialEntryMode = material.DatePickerEntryMode.calendar,
  material.SelectableDayPredicate? selectableDayPredicate,
  String? helpText,
  String? cancelText,
  String? confirmText,
  material.Locale? locale,
  bool useRootNavigator = true,
  material.RouteSettings? routeSettings,
  material.TextDirection? textDirection,
  material.TransitionBuilder? builder,
  material.DatePickerMode initialDatePickerMode = material.DatePickerMode.day,
  String? errorFormatText,
  String? errorInvalidText,
  String? fieldHintText,
  String? fieldLabelText,
  material.TextInputType? keyboardType,
  material.Offset? anchorPoint,
  material.ValueChanged<material.DatePickerEntryMode>? onDatePickerModeChange,
  material.Icon? switchToInputEntryModeIcon,
  material.Icon? switchToCalendarEntryModeIcon,
}) {
  return material.showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    currentDate: currentDate,
    initialEntryMode: initialEntryMode,
    selectableDayPredicate: selectableDayPredicate,
    helpText: helpText,
    cancelText: cancelText,
    confirmText: confirmText,
    locale: locale,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    textDirection: textDirection,
    initialDatePickerMode: initialDatePickerMode,
    errorFormatText: errorFormatText,
    errorInvalidText: errorInvalidText,
    fieldHintText: fieldHintText,
    fieldLabelText: fieldLabelText,
    keyboardType: keyboardType,
    anchorPoint: anchorPoint,
    onDatePickerModeChange: onDatePickerModeChange,
    switchToInputEntryModeIcon: switchToInputEntryModeIcon,
    switchToCalendarEntryModeIcon: switchToCalendarEntryModeIcon,
    builder: (ctx, child) {
      final media = material.MediaQuery.of(ctx);
      final scale = media.textScaler.scale(1.0).clamp(1.0, 1.30);
      final safeChild = child ?? const material.SizedBox.shrink();
      final wrapped = material.MediaQuery(
        data: media.copyWith(textScaler: material.TextScaler.linear(scale)),
        child: safeChild,
      );
      return builder != null ? builder(ctx, wrapped) : wrapped;
    },
  );
}
