import 'package:flutter/material.dart';
import '../constants/link_utils_icons.dart';

/// Modelo de dados para cada célula do grid de seleção de ícones.
/// Retorno definitivo: Navigator.pop(context, item).
class CustomIconData {
  final IconData icon;
  final Color color;
  /// Índice na lista (0-9 por estilo). Usado para highlight e LinkUtilItem.iconIndex.
  final int linkUtilIconIndex;

  const CustomIconData({
    required this.icon,
    required this.color,
    required this.linkUtilIconIndex,
  });
}

/// Conjunto Moderno (estilo pastel) — listas estáticas, sem geração aleatória.
final List<CustomIconData> iconesModernos = [
  const CustomIconData(icon: Icons.description, color: Colors.blue, linkUtilIconIndex: 0),
  const CustomIconData(icon: Icons.search, color: Colors.pink, linkUtilIconIndex: 1),
  const CustomIconData(icon: Icons.attach_money, color: Colors.green, linkUtilIconIndex: 2),
  const CustomIconData(icon: Icons.calendar_today, color: Colors.lightBlue, linkUtilIconIndex: 3),
  const CustomIconData(icon: Icons.language, color: Colors.orange, linkUtilIconIndex: 4),
  const CustomIconData(icon: Icons.access_time, color: Colors.indigo, linkUtilIconIndex: 5),
  const CustomIconData(icon: Icons.shopping_cart, color: Colors.purple, linkUtilIconIndex: 6),
  const CustomIconData(icon: Icons.home, color: Colors.teal, linkUtilIconIndex: 7),
  const CustomIconData(icon: Icons.email, color: Colors.red, linkUtilIconIndex: 8),
  const CustomIconData(icon: Icons.lock, color: Colors.amber, linkUtilIconIndex: 9),
];

/// Conjunto Web/Sistema (estilo colorido/glossy) — baseado em ícones redondos vibrantes.
final List<CustomIconData> iconesColoridos = [
  const CustomIconData(icon: Icons.mail_outline, color: Colors.blue, linkUtilIconIndex: 0),
  const CustomIconData(icon: Icons.person_outline, color: Colors.purple, linkUtilIconIndex: 1),
  const CustomIconData(icon: Icons.phone_android, color: Colors.green, linkUtilIconIndex: 2),
  const CustomIconData(icon: Icons.public, color: Colors.blue, linkUtilIconIndex: 3),
  const CustomIconData(icon: Icons.home_work, color: Colors.red, linkUtilIconIndex: 4),
  const CustomIconData(icon: Icons.settings, color: Colors.blueGrey, linkUtilIconIndex: 5),
  const CustomIconData(icon: Icons.favorite, color: Colors.red, linkUtilIconIndex: 6),
  const CustomIconData(icon: Icons.add_circle, color: Colors.cyan, linkUtilIconIndex: 7),
  const CustomIconData(icon: Icons.download_for_offline, color: Colors.orange, linkUtilIconIndex: 8),
  CustomIconData(icon: Icons.folder, color: Colors.yellow.shade800, linkUtilIconIndex: 9),
];

/// Quantidade de ícones por conjunto (para preview no formulário).
const int kLinkUtilIconCount = 10;

/// Lista para compatibilidade e restauração de links antigos (índice em kLinkUtilIcons).
final List<CustomIconData?> iconGridList = () {
  final list = <CustomIconData?>[];
  for (var i = 0; i < kLinkUtilIcons.length; i++) {
    list.add(CustomIconData(
      icon: kLinkUtilIcons[i],
      color: linkUtilIconColor(i),
      linkUtilIconIndex: i,
    ));
  }
  return list;
}();
