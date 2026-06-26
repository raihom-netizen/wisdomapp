/// Resultado ao fechar o lançamento expresso (inclui IDs para «Desfazer» lote).
class SmartInputPopResult {
  /// IDs dos documentos em `transactions` criados nesta sessão (vazio se cancelou).
  final List<String> createdTransactionIds;

  const SmartInputPopResult({this.createdTransactionIds = const []});

  bool get hasCreated => createdTransactionIds.isNotEmpty;
}
