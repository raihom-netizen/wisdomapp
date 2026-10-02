/**
 * Guardas de permissão do Painel Admin do WISDOMAPP (02/10/2026).
 *
 * MASTER = SOMENTE os e-mails dos donos, conferidos no TOKEN (e-mail
 * verificado). `users.role == 'master'` gravado no Firestore NÃO dá master a
 * ninguém: quem tem esse papel sem ser dono vale como «admin» comum.
 *
 * Níveis (users.role + users.adminLevel, mesmo mapa do app em
 * `lib/services/admin_permissions_service.dart`):
 *   master  → dono por e-mail (tudo, inclusive equipe e ações destrutivas)
 *   admin   → role admin/master sem adminLevel (painel completo, menos o
 *             que é só do master)
 *   suporte → role admin + adminLevel 'suporte' (usuários e licenças)
 *   editor  → role admin + adminLevel 'editor' (divulgação e escalas)
 * `adminCapability` 'finance'/'readonly' (override antigo) vira 'financeiro'
 * / 'leitura'. Gestor, sócio e editor de conteúdo NÃO passam aqui.
 */

const { HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const MASTER_EMAILS = Object.freeze(["raihom@gmail.com", "isabelle.krdoso@gmail.com"]);

function normEmail(v) {
  return (v || "").toString().trim().toLowerCase();
}

/** true quando o token (req.auth.token) é de um dono com e-mail verificado. */
function isMasterToken(token) {
  if (!token || typeof token !== "object") return false;
  if (token.email_verified !== true) return false;
  return MASTER_EMAILS.includes(normEmail(token.email));
}

function authDe(reqOrAuth) {
  if (!reqOrAuth) return null;
  if (reqOrAuth.auth !== undefined) return reqOrAuth.auth || null;
  if (reqOrAuth.uid) return reqOrAuth;
  return null;
}

/** Nível do painel a partir do doc users/{uid} (sem considerar o e-mail). */
function nivelDoPerfil(data) {
  const d = data || {};
  const role = (d.role || "").toString().trim().toLowerCase();
  if (role !== "admin" && role !== "master") return "";
  const lvl = (d.adminLevel || "").toString().trim().toLowerCase();
  if (lvl === "suporte" || lvl === "support") return "suporte";
  if (lvl === "editor") return "editor";
  const cap = (d.adminCapability || "").toString().trim().toLowerCase();
  if (cap === "finance" || cap === "financeiro") return "financeiro";
  if (cap === "readonly" || cap === "leitura") return "leitura";
  if (cap === "support" || cap === "suporte") return "suporte";
  return "admin";
}

/**
 * Nível efetivo: 'master' | 'admin' | 'suporte' | 'editor' | 'financeiro' |
 * 'leitura' | '' (sem acesso de admin).
 */
async function nivelAdmin(reqOrAuth) {
  const auth = authDe(reqOrAuth);
  if (!auth || !auth.uid) return "";
  if (isMasterToken(auth.token)) return "master";
  const snap = await admin.firestore().doc(`users/${auth.uid}`).get();
  return nivelDoPerfil(snap.data());
}

/** Só os donos (e-mail verificado do token). */
async function requireMaster(req, msg) {
  const auth = authDe(req);
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "Faça login.");
  }
  if (!isMasterToken(auth.token)) {
    throw new HttpsError(
      "permission-denied",
      msg || "Somente o master (dono do sistema) pode fazer isso.",
    );
  }
  return "master";
}

/**
 * Exige um dos níveis em [niveis] (master sempre passa). Ex.:
 * `await requireAdminLevel(req, ["admin", "suporte"])`.
 */
async function requireAdminLevel(req, niveis, msg) {
  const auth = authDe(req);
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "Faça login.");
  }
  const nivel = await nivelAdmin(auth);
  if (nivel === "master") return nivel;
  const ok = Array.isArray(niveis) ? niveis : [niveis];
  if (!nivel || !ok.includes(nivel)) {
    throw new HttpsError(
      "permission-denied",
      msg || "Seu nível na equipe não permite esta ação.",
    );
  }
  return nivel;
}

/** Grava em activity_logs (não derruba a ação se falhar). */
async function logAdmin(req, acao, detalhes, extra) {
  try {
    const auth = authDe(req) || {};
    await admin.firestore().collection("activity_logs").add({
      modulo: "Admin",
      acao: (acao || "").toString(),
      detalhes: (detalhes || "").toString(),
      adminId: auth.uid || null,
      adminEmail: normEmail(auth.token && auth.token.email) || null,
      origem: "servidor",
      ...(extra && typeof extra === "object" ? extra : {}),
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.warn("logAdmin:", e && e.message ? e.message : e);
  }
}

module.exports = {
  MASTER_EMAILS,
  normEmail,
  isMasterToken,
  nivelDoPerfil,
  nivelAdmin,
  requireMaster,
  requireAdminLevel,
  logAdmin,
};
