import 'package:flutter/material.dart';

export 'external_calendar_integration_panel.dart';

/// Apple Calendar está no [ExternalCalendarIntegrationPanel] (iOS).
/// Mantido só para não quebrar imports — não renderiza nada extra.
class AppleCalendarIntegrationToggle extends StatelessWidget {
  const AppleCalendarIntegrationToggle({
    super.key,
    required this.userDocId,
    this.onChanged,
    this.compact = false,
  });

  final String userDocId;
  final VoidCallback? onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
