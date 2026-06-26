import 'package:cloud_firestore/cloud_firestore.dart';

/// Uma anotação do módulo Minhas Anotações: título, data, cor (categoria), lista de itens, fixar no topo.
class NoteEntry {
  final String id;
  final String title;
  final DateTime date;
  /// Índice de cor: 0=verde, 1=laranja, 2=azul, 3=roxo
  final int colorIndex;
  final List<String> items;
  final bool isPinned;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const NoteEntry({
    required this.id,
    required this.title,
    required this.date,
    this.colorIndex = 0,
    this.items = const [],
    this.isPinned = false,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'date': Timestamp.fromDate(date),
      'colorIndex': colorIndex,
      'items': items,
      'isPinned': isPinned,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static NoteEntry fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final date = (d['date'] as Timestamp?)?.toDate() ?? DateTime.now();
    final itemsList = d['items'];
    final items = itemsList is List
        ? itemsList.map((e) => e?.toString() ?? '').toList()
        : <String>[];
    final rawColor = d['colorIndex'];
    int colorIndex = 0;
    if (rawColor is int) {
      colorIndex = rawColor;
    } else if (rawColor is num) {
      colorIndex = rawColor.toInt();
    }
    return NoteEntry(
      id: doc.id,
      title: (d['title'] ?? '').toString(),
      date: date,
      colorIndex: colorIndex,
      items: items,
      isPinned: (d['isPinned'] as bool?) ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  NoteEntry copyWith({
    String? id,
    String? title,
    DateTime? date,
    int? colorIndex,
    List<String>? items,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      colorIndex: colorIndex ?? this.colorIndex,
      items: items ?? this.items,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
