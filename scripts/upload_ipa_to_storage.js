/**
 * Envia o IPA do WISDOMAPP para Firebase Storage (app/ipa/WISDOMAPP_app.ipa).
 * Uso no Codemagic: FIREBASE_SERVICE_ACCOUNT_JSON no grupo firebase_ipa_upload.
 * Uso local: node scripts/upload_ipa_to_storage.js [caminho-do.ipa]
 */
const fs = require('fs');
const path = require('path');
const https = require('https');
const crypto = require('crypto');

const BUCKET = process.env.FIREBASE_STORAGE_BUCKET || 'wisdomapp-b9e98.firebasestorage.app';
const DEST = 'app/ipa/WISDOMAPP_app.ipa';

function getServiceAccount() {
  const json = process.env.FIREBASE_SERVICE_ACCOUNT_JSON || process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON;
  if (json) {
    try {
      return typeof json === 'string' ? JSON.parse(json) : json;
    } catch (e) {
      console.error('FIREBASE_SERVICE_ACCOUNT_JSON inválido');
      process.exit(1);
    }
  }
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (credPath && fs.existsSync(credPath)) {
    return JSON.parse(fs.readFileSync(credPath, 'utf8'));
  }
  console.error('Defina FIREBASE_SERVICE_ACCOUNT_JSON ou GOOGLE_APPLICATION_CREDENTIALS.');
  process.exit(1);
}

function getIpaPath() {
  const arg = process.argv[2];
  if (arg && fs.existsSync(arg)) return path.resolve(arg);
  const root = path.join(__dirname, '..');
  const ipaDir = path.join(root, 'build', 'ios', 'ipa');
  if (fs.existsSync(ipaDir)) {
    const files = fs.readdirSync(ipaDir).filter(f => f.endsWith('.ipa'));
    if (files.length) return path.join(ipaDir, files[0]);
  }
  console.error('Nenhum .ipa encontrado. Passe o caminho: node upload_ipa_to_storage.js /caminho/arquivo.ipa');
  process.exit(1);
}

function createJwt(sa) {
  const header = { alg: 'RS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: sa.client_email,
    sub: sa.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/cloud-platform',
  };
  const b64url = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const signatureInput = b64url(header) + '.' + b64url(payload);
  const sign = crypto.createSign('RSA-SHA256');
  sign.update(signatureInput);
  const sig = sign.sign(sa.private_key).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return signatureInput + '.' + sig;
}

function fetchToken(sa) {
  return new Promise((resolve, reject) => {
    const jwt = createJwt(sa);
    const body = 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=' + encodeURIComponent(jwt);
    const req = https.request({
      hostname: 'oauth2.googleapis.com',
      path: '/token',
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(body) },
    }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        try {
          const j = JSON.parse(data);
          if (j.access_token) resolve(j.access_token);
          else reject(new Error(j.error_description || data));
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function uploadToGcs(accessToken, filePath, contentType) {
  return new Promise((resolve, reject) => {
    const fileBuffer = fs.readFileSync(filePath);
    const url = `https://storage.googleapis.com/upload/storage/v1/b/${BUCKET}/o?uploadType=media&name=${encodeURIComponent(DEST)}`;
    const u = new URL(url);
    const req = https.request({
      hostname: u.hostname,
      path: u.pathname + u.search,
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + accessToken,
        'Content-Type': contentType || 'application/octet-stream',
        'Content-Length': fileBuffer.length,
      },
    }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve();
        } else {
          reject(new Error('Upload falhou: ' + res.statusCode + ' ' + data));
        }
      });
    });
    req.on('error', reject);
    req.write(fileBuffer);
    req.end();
  });
}

async function main() {
  const ipaPath = getIpaPath();
  const sa = getServiceAccount();
  const sizeMB = (fs.statSync(ipaPath).size / (1024 * 1024)).toFixed(2);
  console.log('IPA:', ipaPath, '(' + sizeMB + ' MB)');
  const token = await fetchToken(sa);
  await uploadToGcs(token, ipaPath, 'application/octet-stream');
  const publicUrl = 'https://firebasestorage.googleapis.com/v0/b/' + BUCKET + '/o/app%2Fipa%2FWISDOMAPP_app.ipa?alt=media';
  console.log('IPA enviado para', DEST);
  console.log('Link na divulgação:', publicUrl);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
