import 'package:flutter/foundation.dart' show compute;

import '../services/bank_notification_parser.dart';

/// Entrada para [runSmartInputHeavyParse] (isolado em mobile/desktop).
class SmartInputHeavyParseInput {
  final String text;
  const SmartInputHeavyParseInput(this.text);
}

/// Resultado de parse + contagem de linhas em massa num único passe pesado.
class SmartInputHeavyParseOutput {
  final BankNotificationParseResult parsed;
  final int batchCount;
  const SmartInputHeavyParseOutput(this.parsed, this.batchCount);
}

SmartInputHeavyParseOutput _smartInputHeavyParseWorker(SmartInputHeavyParseInput msg) {
  final t = msg.text;
  final (BankNotificationParseResult preview, int batchCount) = BankNotificationParser.parseForSmartInputField(t);
  return SmartInputHeavyParseOutput(preview, batchCount);
}

/// Corre [parse] e [parseManyForBatch] fora do isolado principal (Android/iOS/desktop).
Future<SmartInputHeavyParseOutput> runSmartInputHeavyParse(String text) {
  return compute(_smartInputHeavyParseWorker, SmartInputHeavyParseInput(text));
}
