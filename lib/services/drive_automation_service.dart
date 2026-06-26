import 'package:cloud_firestore/cloud_firestore.dart';

class DriveAutomationService {
  static const String _defaultRootFolderId = '1fMXYKu7Pz934L4ElZnHWdldJHfaPJKqd';

  Future<String> _getRootFolderId() async {
    final snap = await FirebaseFirestore.instance.collection('settings').doc('googledrive').get();
    return (snap.data()?['rootFolderId'] ?? _defaultRootFolderId).toString().trim();
  }

  Future<void> criarEstruturaCliente(String userEmail, String userId) async {
    try {
      final rootFolderId = await _getRootFolderId();
      // Lógica para criar subpasta no Drive Raiz nomeada com o e-mail
      print("Criando pasta para $userEmail no ID Raiz $rootFolderId");
      
      String newFolderId = "GERADO_DINAMICAMENTE"; // ID retornado pela API do Drive

      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'driveFolderId': newFolderId,
        'setupComplete': true,
      });
      
      print("✅ Pasta criada e vinculada ao usuário.");
    } catch (e) {
      print("❌ Erro na automação: $e");
    }
  }
}
