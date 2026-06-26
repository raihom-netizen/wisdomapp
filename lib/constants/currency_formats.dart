import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Formatação padronizada de valores em Real (BRL) em TODO o sistema.
/// Sempre use [formatBRL] para exibir valores monetários.
/// Formato: positivo = "R$ 800.000,00"; negativo = "R$ - 800.000,00" (símbolo R$ e "R$ -" para negativo).
/// Milhares: ponto; decimais: vírgula; sempre 2 casas decimais.
class CurrencyFormats {
  CurrencyFormats._();

  static final NumberFormat _brl = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$ ',
    decimalDigits: 2,
  );

  /// Formata valor em Real: "R$ 800.000,00" (positivo) ou "R$ - 800.000,00" (negativo).
  static String formatBRL(num? value) {
    if (value == null) return 'R\$ 0,00';
    final v = value.toDouble();
    if (v < 0) {
      final abs = _brl.format(-v).replaceFirst('R\$ ', '').trim();
      return 'R\$ - $abs';
    }
    return _brl.format(v);
  }

  /// Formata percentual pt-BR: 89%, 5,2%, 0,4%.
  static String formatPercentBr(double pct) {
    final v = pct.abs();
    if (v < 0.05) return '0%';
    if (v >= 10) return '${pct.toStringAsFixed(0)}%';
    return '${pct.toStringAsFixed(1)}%';
  }

  /// Mesmo que [formatBRL], mas com espaços normais trocados por NBSP — evita quebra no meio
  /// de "R$ 3.852,42" quando o utilizador aumenta zoom/texto (telas estreitas / legendas).
  static String formatBRLTight(num? value) =>
      formatBRL(value).replaceAll(' ', '\u00A0');

  /// Apenas a parte numérica (sem símbolo): "800.000,00" ou "- 800.000,00".
  /// Prefira [formatBRL] para exibição; use este só quando precisar montar "R$" separado.
  static String formatBRLNumberOnly(num? value) {
    if (value == null) return '0,00';
    final v = value.toDouble();
    final formatted = _brl.format(v.abs()).replaceFirst('R\$ ', '').trim();
    return v < 0 ? '- $formatted' : formatted;
  }

  /// Formato para campo de entrada (sem R\$): "1.234,56". Use para valor inicial do TextField.
  static String formatBRLInput(num? value) {
    if (value == null || value.isNaN) return '';
    final v = value.toDouble().clamp(0, double.infinity);
    return _brl.format(v).replaceFirst('R\$ ', '').trim();
  }

  /// Parte inteira com separador de milhar (pt_BR), sem intl — uso interno no teclado.
  static String _thousandsBr(int n) {
    if (n <= 0) return n.toString();
    final s = n.toString();
    final buf = StringBuffer();
    final len = s.length;
    for (var i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// Máscara BRL a partir de centavos (ex.: 25000 → "250,00"), **sem** [NumberFormat].
  /// Usado no [CurrencyInputFormatter] para não travar o frame a cada tecla.
  static String formatBRLInputFromCents(int cents) {
    if (cents < 0) cents = 0;
    final reais = cents ~/ 100;
    final c = (cents % 100).toString().padLeft(2, '0');
    return '${_thousandsBr(reais)},$c';
  }

  /// Converte texto do campo (máscara "1.234,56" ou "100" ou "100,5") para [double]. Retorna null se inválido.
  static double? parseBRLInput(String text) {
    final t = text.trim().replaceAll('.', '').replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  /// Máscara para campo de valor: ao digitar mostra "100,00", "1.000,00" etc. (padrão BR).
  /// Instância única evita recriar o formatter a cada rebuild (menos trabalho ao abrir teclado).
  static final List<TextInputFormatter> brlInputFormatters = [CurrencyInputFormatter()];
}

/// Formatter que aplica máscara BRL enquanto o usuário digita (1.234,56).
/// Usa "centavos": todos os dígitos formam um inteiro; os 2 últimos = decimais. Ex.: 25000 -> 250,00.
/// Assim "2" "5" "0" "0" "0" exibe 250,00 (não 2,00 ao digitar o 2).
class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final onlyDigits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (onlyDigits.isEmpty) return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    final cents = int.tryParse(onlyDigits) ?? 0;
    final formatted = CurrencyFormats.formatBRLInputFromCents(cents);
    if (formatted.isEmpty) return newValue;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
