import '../models/finance_tip_bank_entry.dart';
import 'financial_tips_firestore_seed_bank.dart';

/// Banco fixo de dicas (fallback local + espelho do seed Firestore).
///
/// Fonte única: [kFinancialTipsFirestoreSeedBank]. Importe no admin para `financial_tips`.
final List<FinanceTipBankEntry> kFinanceTipBankStatic = buildFinanceTipBankFromSeed();

/// Mapa rápido por id (updates Firestore podem sobrepor cópia local).
FinanceTipBankEntry? financeTipBankEntryById(String id) {
  for (final e in kFinanceTipBankStatic) {
    if (e.id == id) return e;
  }
  return null;
}
