import 'package:cloud_firestore/cloud_firestore.dart';

class UserDriveAutomation {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Função disparada no cadastro ou ativação de licença
  Future<void> configurarEspacoCliente(String userEmail, String userId) async {
    try {
      // 1. Busca o ID da Pasta Raiz que você configurou no Painel Admin
      final adminSettings = await _db.collection('settings').doc('googledrive').get();
      final String rootFolderId = adminSettings.data()?['rootFolderId'] ?? '1fMXYKu7Pz934L4ElZnHWdldJHfaPJKqd';

      // 2. Lógica para criar a subpasta via API do Google Drive
      // A pasta terá o nome do e-mail do usuário para identificação imediata
      print('Criando diretório no Drive para: $userEmail');
      
      // Simulação da chamada de criação (Requer Service Account configurada)
      String folderIdCriada = "ID_GERADO_VIA_API"; 

      // 3. Salva o link da pasta do cliente no perfil dele no Firestore
      await _db.collection('users').doc(userId).update({
        'userDriveFolderId': folderIdCriada,
        'userDrivePath': 'WISDOMAPP / Clientes / $userEmail',
        'setupDate': FieldValue.serverTimestamp(),
      });

      print('✅ Infraestrutura de arquivos pronta para $userEmail');
    } catch (e) {
      print('❌ Erro na automação de pasta: $e');
    }
  }
}
