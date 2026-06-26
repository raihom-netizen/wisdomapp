import 'package:flutter/material.dart';

import 'bank_brand_assets.dart';

/// Bancos em destaque na vitrine: [id] liga ao ficheiro offline `assets/images/bank_brands/{id}.png`.
class SpotlightBank {
  const SpotlightBank({
    required this.id,
    required this.name,
    required this.shortLabel,
    required this.placeholderColor,
    required this.icon,
  });

  /// Chave do asset em [BankBrandAssets.pngPath].
  final String id;
  final String name;
  final String shortLabel;
  final Color placeholderColor;
  final IconData icon;

  String get localLogoPngPath => BankBrandAssets.pngPath(id);
}

const List<SpotlightBank> kSpotlightBanks = [
  SpotlightBank(id: 'nubank', name: 'Nubank', shortLabel: 'Nu', placeholderColor: Color(0xFF8A05BE), icon: Icons.credit_card_rounded),
  SpotlightBank(id: 'itau', name: 'Itaú', shortLabel: 'It', placeholderColor: Color(0xFFEC7000), icon: Icons.account_balance_rounded),
  SpotlightBank(id: 'bradesco', name: 'Bradesco', shortLabel: 'Br', placeholderColor: Color(0xFFCC092F), icon: Icons.account_balance_rounded),
  SpotlightBank(id: 'bb', name: 'Banco do Brasil', shortLabel: 'BB', placeholderColor: Color(0xFFFFEF42), icon: Icons.account_balance_rounded),
  SpotlightBank(id: 'santander', name: 'Santander', shortLabel: 'Sa', placeholderColor: Color(0xFFEC0000), icon: Icons.account_balance_rounded),
  SpotlightBank(id: 'caixa', name: 'Caixa', shortLabel: 'Cx', placeholderColor: Color(0xFF003366), icon: Icons.account_balance_rounded),
  SpotlightBank(id: 'inter', name: 'Inter', shortLabel: 'In', placeholderColor: Color(0xFFFF7A00), icon: Icons.flash_on_rounded),
  SpotlightBank(id: 'c6', name: 'C6 Bank', shortLabel: 'C6', placeholderColor: Color(0xFF000000), icon: Icons.layers_rounded),
  SpotlightBank(id: 'mercado_pago', name: 'Mercado Pago', shortLabel: 'MP', placeholderColor: Color(0xFF009EE3), icon: Icons.payments_rounded),
  SpotlightBank(id: 'picpay', name: 'PicPay', shortLabel: 'PP', placeholderColor: Color(0xFF21C25E), icon: Icons.phone_android_rounded),
];
