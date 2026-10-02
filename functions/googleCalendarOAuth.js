/**
 * Google Calendar OAuth — Authorization Code + refresh_token (servidor).
 * Segredo: GOOGLE_OAUTH_CLIENT_SECRET (Firebase params / .env functions).
 */
const functions = require("firebase-functions");
const { onCall } = require("firebase-functions/v2/https");
const { google } = require("googleapis");
const admin = require("firebase-admin");

const DEFAULT_WEB_CLIENT_ID =
  "766524666378-ce9albkkvn01si77s6ofcqvoaatn29s0.apps.googleusercontent.com";
const DEFAULT_REDIRECT_URI =
  "https://wisdomapp-b9e98.web.app/google_calendar_oauth.html";

function clientId() {
  return (
    functions.config().app?.google_web_client_id ||
    process.env.GOOGLE_WEB_CLIENT_ID ||
    DEFAULT_WEB_CLIENT_ID
  )
    .toString()
    .trim();
}

function clientSecret() {
  return (
    functions.config().app?.google_oauth_client_secret ||
    process.env.GOOGLE_OAUTH_CLIENT_SECRET ||
    ""
  )
    .toString()
    .trim();
}

function privateOAuthRef(uid) {
  return admin.firestore().doc(`users/${uid}/private/google_calendar_oauth`);
}

function settingsRef(uid) {
  return admin
    .firestore()
    .doc(`users/${uid}/settings/google_calendar_integration`);
}

function oauth2Client(redirectUri) {
  const secret = clientSecret();
  if (!secret) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "GOOGLE_OAUTH_CLIENT_SECRET não configurado nas Cloud Functions.",
    );
  }
  return new google.auth.OAuth2(clientId(), secret, redirectUri || DEFAULT_REDIRECT_URI);
}

async function fetchGoogleEmail(accessToken) {
  if (!accessToken) return null;
  try {
    const oauth2 = oauth2Client(DEFAULT_REDIRECT_URI);
    oauth2.setCredentials({ access_token: accessToken });
    const oauth2Api = google.oauth2({ version: "v2", auth: oauth2 });
    const { data } = await oauth2Api.userinfo.get();
    const email = (data.email || "").toString().trim();
    return email || null;
  } catch (_) {
    return null;
  }
}

async function persistTokens(uid, tokens, emailHint) {
  const refreshToken = (tokens.refresh_token || "").toString().trim();
  const accessToken = (tokens.access_token || "").toString().trim();
  const expiresAt =
    typeof tokens.expiry_date === "number" ? tokens.expiry_date : null;
  const email =
    emailHint || (await fetchGoogleEmail(accessToken)) || "";

  const privatePayload = {
    accessToken,
    expiresAt,
    scope: (tokens.scope || "").toString(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (refreshToken) {
    privatePayload.refreshToken = refreshToken;
    privatePayload.refreshTokenUpdatedAt =
      admin.firestore.FieldValue.serverTimestamp();
  }

  await privateOAuthRef(uid).set(privatePayload, { merge: true });

  const after = await privateOAuthRef(uid).get();
  const hasRefreshToken = Boolean(
    (after.data()?.refreshToken || "").toString().trim(),
  );

  const settingsPatch = {
    hasRefreshToken,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (email) settingsPatch.connectedEmail = email;
  await settingsRef(uid).set(settingsPatch, { merge: true });

  return { accessToken, expiresAt, email, hasRefreshToken };
}

/** Erro do Google OAuth → mensagem clara para o app (sem expor segredos). */
function googleOAuthHttpsError(e, acao) {
  const raw = (e?.response?.data?.error || e?.message || "").toString();
  console.warn(`googleCalendarOAuth (${acao}):`, raw);
  if (raw.includes("invalid_grant")) {
    return new functions.https.HttpsError(
      "failed-precondition",
      "A autorização do Google expirou ou foi revogada. Ative o Google Calendar de novo.",
    );
  }
  if (raw.includes("redirect_uri_mismatch")) {
    return new functions.https.HttpsError(
      "failed-precondition",
      "Configuração do Google OAuth (redirect) não confere. Avise o suporte.",
    );
  }
  if (raw.includes("invalid_client") || raw.includes("unauthorized_client")) {
    return new functions.https.HttpsError(
      "failed-precondition",
      "Cliente Google OAuth inválido no servidor. Avise o suporte.",
    );
  }
  return new functions.https.HttpsError(
    "unavailable",
    `Não foi possível ${acao} no Google agora. Tente de novo em instantes.`,
  );
}

async function refreshAccessTokenForUid(uid) {
  const snap = await privateOAuthRef(uid).get();
  const data = snap.data() || {};
  const refreshToken = (data.refreshToken || "").toString().trim();
  if (!refreshToken) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Refresh token ausente. Reautorize o Calendário Google.",
    );
  }

  const oauth2 = oauth2Client(DEFAULT_REDIRECT_URI);
  oauth2.setCredentials({ refresh_token: refreshToken });
  let credentials;
  try {
    ({ credentials } = await oauth2.refreshAccessToken());
  } catch (e) {
    throw googleOAuthHttpsError(e, "renovar o acesso");
  }
  const saved = await persistTokens(uid, credentials, data.connectedEmail || null);
  return saved;
}

async function disconnectUid(uid) {
  const snap = await privateOAuthRef(uid).get();
  const data = snap.data() || {};
  const token = (data.refreshToken || data.accessToken || "").toString().trim();
  if (token) {
    try {
      const oauth2 = oauth2Client(DEFAULT_REDIRECT_URI);
      await oauth2.revokeToken(token);
    } catch (_) {}
  }
  await privateOAuthRef(uid).delete();
  await settingsRef(uid).set(
    {
      hasRefreshToken: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function assertAuth(req) {
  if (!req.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Login necessário.");
  }
  return req.auth.uid;
}

/** Troca authorization code por access + refresh token (Web OAuth). */
exports.ctGoogleCalendarExchangeCode = onCall(async (req) => {
  const uid = assertAuth(req);
  const code = (req.data?.code || "").toString().trim();
  const redirectUri =
    (req.data?.redirectUri || DEFAULT_REDIRECT_URI).toString().trim();
  if (!code) {
    throw new functions.https.HttpsError("invalid-argument", "code obrigatório.");
  }

  const oauth2 = oauth2Client(redirectUri);
  let tokens;
  try {
    ({ tokens } = await oauth2.getToken(code));
  } catch (e) {
    throw googleOAuthHttpsError(e, "concluir a autorização");
  }
  if (!tokens.access_token) {
    throw new functions.https.HttpsError(
      "internal",
      "Google não devolveu access_token.",
    );
  }

  const saved = await persistTokens(uid, tokens, null);
  return {
    ok: true,
    accessToken: saved.accessToken,
    expiresAt: saved.expiresAt,
    email: saved.email,
    hasRefreshToken: saved.hasRefreshToken,
  };
});

/** Renova access_token silenciosamente via refresh_token salvo. */
exports.ctGoogleCalendarRefreshAccessToken = onCall(async (req) => {
  const uid = assertAuth(req);
  const saved = await refreshAccessTokenForUid(uid);
  return {
    ok: true,
    accessToken: saved.accessToken,
    expiresAt: saved.expiresAt,
    email: saved.email,
  };
});

/** Revoga tokens Google e remove credenciais privadas. */
exports.ctGoogleCalendarDisconnect = onCall(async (req) => {
  const uid = assertAuth(req);
  await disconnectUid(uid);
  return { ok: true };
});

module.exports.refreshAccessTokenForUid = refreshAccessTokenForUid;
module.exports.disconnectUid = disconnectUid;
module.exports.privateOAuthRef = privateOAuthRef;
module.exports.settingsRef = settingsRef;
module.exports.oauth2Client = oauth2Client;
module.exports.clientId = clientId;
