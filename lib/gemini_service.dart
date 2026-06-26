import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  // Substitua pela sua chave de API do Google AI Studio
  final String _apiKey = "SUA_CHAVE_AQUI";
  
  Future<String> obterDicaMeta(String objetivo, double valor) async {
    try {
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
      
      final prompt = "Aja como um consultor financeiro. O usuário quer atingir a meta de $objetivo no valor de R\$ $valor. " +
                     "Dê uma dica curta, prática e motivadora de no máximo 3 frases.";
      
      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      
      return response.text ?? "IA: Continue focado na sua meta!";
    } catch (e) {
      return "IA: No momento não consegui analisar, mas mantenha o foco no seu objetivo!";
    }
  }
}
