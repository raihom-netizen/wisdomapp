import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import '../models/note_entry.dart';
import '../utils/firestore_user_doc_id.dart';

List<NoteEntry> _noteEntriesFromQuerySnapshot(
    QuerySnapshot<Map<String, dynamic>> snap) {
  final list = snap.docs.map(NoteEntry.fromDoc).toList();
  list.sort((a, b) =>
      (b.updatedAt ?? b.date).compareTo(a.updatedAt ?? a.date));
  return list;
}

/// Serviço Firestore para anotações do usuário: users/{uid}/notes
class NotesService {
  CollectionReference<Map<String, dynamic>> _notesRef(String uid) => FirebaseFirestore.instance
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('notes');

  /// Lê sempre `users/{request.auth.uid}/…`. Sem sessão, não liga o Firestore (evita
  /// [permission-denied] na web com token ainda a restaurar).
  ///
  /// **Sem `orderBy` na query** — a ordenação é feita no cliente (igual outras coleções
  /// que evitaram índice / falhas intermitentes na web). Lista completa em memória.
  ///
  /// **Cache-first**: após a sessão existir, faz um `get(source: cache)` e emite logo
  /// (anotações antigas aparecem na hora); em seguida liga `snapshots()` para o servidor.
  ///
  /// [asBroadcastStream] após o pipeline: o upstream do Firestore é subscrição única;
  /// vários widgets podem ouvir sem falhas silenciosas.
  Stream<List<NoteEntry>> streamNotes(String uid) {
    return fa.FirebaseAuth.instance.authStateChanges().asyncExpand((user) async* {
      if (user == null) {
        yield const <NoteEntry>[];
        return;
      }
      final pathId = firestoreUserDocIdForAppShell(uid);
      if (pathId.isEmpty) {
        yield const <NoteEntry>[];
        return;
      }
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(pathId)
          .collection('notes');
      try {
        final cached =
            await col.get(const GetOptions(source: Source.cache));
        yield _noteEntriesFromQuerySnapshot(cached);
      } catch (_) {
        yield const <NoteEntry>[];
      }
      yield* col.snapshots().map(_noteEntriesFromQuerySnapshot);
    }).asBroadcastStream();
  }

  Future<void> add(String uid, NoteEntry note) async {
    final ref = _notesRef(uid).doc();
    await ref.set({
      ...note.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> update(String uid, NoteEntry note) async {
    await _notesRef(uid).doc(note.id).update(note.toMap());
  }

  Future<void> delete(String uid, String noteId) async {
    await _notesRef(uid).doc(noteId).delete();
  }
}
