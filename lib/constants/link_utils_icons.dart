import 'package:flutter/material.dart';

/// Modelo de dados para cada opção do grid "Escolher ícone": ícone Material + cor pastel.
class CustomIconOption {
  final IconData icon;
  final Color color;

  const CustomIconOption({required this.icon, required this.color});
}

/// Ícones disponíveis para links úteis (índice = iconIndex salvo no Firestore).
/// Usa variantes padrão do Material Icons para garantir que todos renderizem (sem slots vazios).
const List<IconData> kLinkUtilIcons = [
  // Originais (0-7) — compatibilidade
  Icons.description,
  Icons.public,
  Icons.directions_car,
  Icons.search,
  Icons.gavel,
  Icons.calculate,
  Icons.link,
  Icons.star,
  // Documentos e lei
  Icons.article,
  Icons.menu_book,
  Icons.library_books,
  Icons.balance,
  Icons.account_balance,
  Icons.verified_user,
  Icons.assignment,
  // Finanças e trabalho
  Icons.attach_money,
  Icons.trending_up,
  Icons.savings,
  Icons.work,
  Icons.business_center,
  Icons.receipt,
  Icons.payments,
  // Calendário e tempo
  Icons.calendar_today,
  Icons.event,
  Icons.schedule,
  Icons.access_time,
  Icons.today,
  // Comunicação e rede
  Icons.email,
  Icons.phone,
  Icons.language,
  Icons.explore,
  Icons.wifi,
  Icons.cloud,
  // Lugares e mapas
  Icons.place,
  Icons.map,
  Icons.directions,
  Icons.location_on,
  // Pessoas e saúde
  Icons.person,
  Icons.group,
  Icons.medical_services,
  Icons.local_hospital,
  Icons.school,
  // Ações e ferramentas
  Icons.edit,
  Icons.settings,
  Icons.info,
  Icons.help,
  Icons.lightbulb,
  Icons.bookmark,
  Icons.favorite,
  Icons.share,
  Icons.download,
  Icons.upload,
  Icons.print,
  Icons.home,
  Icons.dashboard,
  Icons.apps,
  // Ícones do seletor Moderno/Colorido (para linkUtilIconForDisplay encontrar por codePoint)
  Icons.shopping_cart,
  Icons.lock,
  Icons.mail_outline,
  Icons.person_outline,
  Icons.phone_android,
  Icons.home_work,
  Icons.add_circle,
  Icons.download_for_offline,
  Icons.folder,
];

/// Paleta de cores modernas para o grid de ícones (usa índice % length).
const List<Color> kLinkUtilIconColors = [
  Color(0xFF3B82F6), // azul
  Color(0xFF6366F1), // índigo
  Color(0xFF8B5CF6), // violeta
  Color(0xFFEC4899), // rosa
  Color(0xFFEF4444), // vermelho
  Color(0xFFF97316), // laranja
  Color(0xFFEAB308), // amarelo
  Color(0xFF22C55E), // verde
  Color(0xFF14B8A6), // teal
  Color(0xFF06B6D4), // ciano
  Color(0xFF0EA5E9), // azul claro
  Color(0xFF7C3AED), // roxo
];

/// Cor do ícone por índice (grid colorido).
Color linkUtilIconColor(int index) =>
    kLinkUtilIconColors[index % kLinkUtilIconColors.length];

/// Ícone que sempre renderiza no módulo Minhas Anotações: evita IconData(codePoint) que pode falhar na web.
/// Busca em [kLinkUtilIcons] por [codePoint]; se não achar, usa [index]. Nunca retorna ícone inválido.
IconData linkUtilIconForDisplay({int? codePoint, int index = 0}) {
  if (codePoint != null) {
    for (final icon in kLinkUtilIcons) {
      if (icon.codePoint == codePoint) return icon;
    }
  }
  final i = index.clamp(0, kLinkUtilIcons.length - 1);
  return kLinkUtilIcons[i];
}

/// Cor para exibição: usa valor salvo ou paleta por índice. Nunca retorna cor inválida.
Color linkUtilColorForDisplay({int? colorValue, int index = 0}) {
  if (colorValue != null) {
    try {
      return Color(colorValue);
    } catch (_) {}
  }
  return linkUtilIconColor(index);
}

/// Lista de opções para o GridView: cada item tem IconData (Material) + Color. Índice = iconIndex.
List<CustomIconOption> get kLinkUtilIconOptions => List.generate(
  kLinkUtilIcons.length,
  (i) => CustomIconOption(icon: kLinkUtilIcons[i], color: linkUtilIconColor(i)),
);
