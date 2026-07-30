const functions = require("firebase-functions");

const ICON_KEYS = [
  "lightbulb",
  "savings",
  "credit_card",
  "trending_up",
  "warning",
  "percent",
  "account_balance",
  "bar_chart",
  "timer",
  "menu_book",
];

const COLOR_KEYS = [
  "primary",
  "blue",
  "green",
  "teal",
  "purple",
  "orange",
  "red",
  "indigo",
];

function resolveGeminiApiKey() {
  const fromEnv = (process.env.GEMINI_API_KEY || "").toString().trim();
  if (fromEnv) return fromEnv;
  try {
    const cfg = functions.config();
    return (cfg?.gemini?.api_key || "").toString().trim();
  } catch (_) {
    return "";
  }
}

function fallbackTip(tema, categoria) {
  const t = (tema || "organização financeira pessoal").toString().trim();
  const cat = (categoria || "educacao").toString().trim() || "educacao";
  return {
    titulo: t.length > 60 ? `${t.slice(0, 57)}…` : t,
    descricao:
      `Dica prática sobre ${t}: registre gastos fixos e variáveis, defina um teto semanal ` +
      `e revise metas no fim do mês. Pequenos hábitos consistentes valem mais que ajustes extremos.`,
    categoria: cat,
    iconKey: "lightbulb",
    colorKey: "blue",
    source: "fallback",
  };
}

function parseJsonFromModelText(text) {
  const raw = (text || "").toString().trim();
  if (!raw) return null;
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = fenced ? fenced[1].trim() : raw;
  try {
    return JSON.parse(candidate);
  } catch (_) {
    const start = candidate.indexOf("{");
    const end = candidate.lastIndexOf("}");
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(candidate.slice(start, end + 1));
      } catch (_) {}
    }
  }
  return null;
}

async function callGemini(apiKey, prompt) {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${encodeURIComponent(apiKey)}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.7,
        maxOutputTokens: 1024,
      },
    }),
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Gemini HTTP ${res.status}: ${errText.slice(0, 200)}`);
  }
  const json = await res.json();
  const parts = json?.candidates?.[0]?.content?.parts || [];
  return parts.map((p) => p.text || "").join("").trim();
}

async function generateFinancialTipWithAI({ tema, categoria, tom }) {
  const apiKey = resolveGeminiApiKey();
  const topic = (tema || "").toString().trim();
  const cat = (categoria || "educacao").toString().trim() || "educacao";
  const tone = (tom || "didático e motivador").toString().trim();

  if (!topic) {
    throw new functions.https.HttpsError("invalid-argument", "Informe o tema da dica.");
  }

  if (!apiKey) {
    return fallbackTip(topic, cat);
  }

  const prompt =
    `Você é especialista em educação financeira para o app WISDOMAPP (Brasil). ` +
    `Crie UMA dica curta e acionável sobre: "${topic}". ` +
    `Tom: ${tone}. Categoria slug sugerida: ${cat}. ` +
    `Responda SOMENTE JSON válido com chaves: titulo (max 70 chars), descricao (2-4 frases, max 320 chars), ` +
    `categoria (slug: educacao|comportamento|alimentacao|cartao|reserva), iconKey (${ICON_KEYS.join("|")}), ` +
    `colorKey (${COLOR_KEYS.join("|")}). Sem markdown fora do JSON.`;

  try {
    const text = await callGemini(apiKey, prompt);
    const parsed = parseJsonFromModelText(text);
    if (!parsed || typeof parsed !== "object") {
      return { ...fallbackTip(topic, cat), source: "fallback_parse" };
    }
    const iconKey = ICON_KEYS.includes(parsed.iconKey) ? parsed.iconKey : "lightbulb";
    const colorKey = COLOR_KEYS.includes(parsed.colorKey) ? parsed.colorKey : "blue";
    return {
      titulo: (parsed.titulo || topic).toString().trim().slice(0, 80),
      descricao: (parsed.descricao || "").toString().trim().slice(0, 500),
      categoria: (parsed.categoria || cat).toString().trim().slice(0, 40),
      iconKey,
      colorKey,
      source: "gemini",
    };
  } catch (e) {
    console.warn("generateFinancialTipWithAI gemini:", e?.message || e);
    return { ...fallbackTip(topic, cat), source: "fallback_error" };
  }
}

module.exports = { generateFinancialTipWithAI };
