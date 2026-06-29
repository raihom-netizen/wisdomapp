import 'package:flutter/material.dart';

import 'external_calendar_integration_panel.dart';

export 'external_calendar_integration_panel.dart';

/// Compatível com imports antigos — delega ao painel unificado Google + Apple.
class GoogleCalendarIntegrationToggle extends StatelessWidget {
  const GoogleCalendarIntegrationToggle({
    super.key,
    required this.userDocId,
    this.onChanged,
    this.compact = false,
    this.showChangeAccountAction = false,
  });

  final String userDocId;
  final VoidCallback? onChanged;
  final bool compact;
  final bool showChangeAccountAction;

  @override
  Widget build(BuildContext context) {
    return ExternalCalendarIntegrationPanel(
      userDocId: userDocId,
      compact: compact,
      showChangeGoogleAccountAction: showChangeAccountAction,
      onGoogleChanged: onChanged,
      onAppleChanged: onChanged,
    );
  }
}
