/// Divisão de um valor total em parcelas — em CENTAVOS.
///
/// Correção autorizada pelo dono (02/10/2026): antes cada parcela era
/// `total / n` sem arredondar (R$ 100 em 3× = 33,333… em cada uma), o que
/// deixava dízimas gravadas e a soma das parcelas exibidas (33,33 × 3 =
/// 99,99) diferente do total. Agora cada parcela tem centavos exatos e a
/// ÚLTIMA absorve a diferença (33,33 + 33,33 + 33,34 = 100,00).
List<double> splitInstallmentsInCents({
  required double total,
  required int installments,
}) {
  final n = installments < 1 ? 1 : installments;
  final totalCents = (total * 100).round();
  final base = totalCents ~/ n;
  return [
    for (var i = 1; i <= n; i++)
      (i == n ? totalCents - base * (n - 1) : base) / 100.0,
  ];
}

/// Divide [items] em lotes de no máximo [size] (WriteBatch aceita até 500
/// gravações; usamos 450 por segurança).
Iterable<List<T>> chunked<T>(List<T> items, {int size = 450}) sync* {
  for (var i = 0; i < items.length; i += size) {
    yield items.sublist(i, i + size > items.length ? items.length : i + size);
  }
}
