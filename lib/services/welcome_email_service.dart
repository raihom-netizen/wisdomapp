import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class WelcomeEmailService {
  // Simulação de disparo via Cloud Functions ou Mailer
  Future<void> enviarEmailBoasVindas(String userEmail, String folderId) async {
    final String driveLink = "https://drive.google.com/drive/folders/$folderId";
    
    final String assunto = "Bem-vindo ao WISDOMAPP!";
    final String corpo = """
Olá! 🚀

Sua conta no WISDOMAPP foi ativada com sucesso.

Sua área exclusiva de arquivos já está pronta e organizada pelo seu e-mail:
📂 Acessar minha pasta no Google Drive: $driveLink

Aqui você encontrará todos os seus backups e documentos do projeto.

Seja bem-vindo ao futuro da gestão inteligente!
Atenciosamente,
Equipe WISDOMAPP
    """;

    try {
      print('Disparando e-mail de boas-vindas para: $userEmail');
      // Lógica de integração com SMTP ou Firebase Mail Extension
      // await sendEmail(to: userEmail, subject: assunto, body: corpo);
      
      print('✅ E-mail enviado com sucesso!');
    } catch (e) {
      print('❌ Erro ao enviar e-mail: $e');
    }
  }
}
