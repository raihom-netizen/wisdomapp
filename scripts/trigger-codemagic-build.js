#!/usr/bin/env node
/**
 * Dispara build iOS no CodeMagic (webhook + API).
 * Token opcional: .codemagic-token ou CODEMAGIC_API_TOKEN
 */
const fs = require('fs');
const path = require('path');
const https = require('https');

const root = path.join(__dirname, '..');
const repo = 'https://github.com/raihom-netizen/wisdomapp.git';
const archivedAppId = '6a3fe39cfbfdda27bec38156';
const branch = process.env.CODEMAGIC_BRANCH || 'main';
const workflowId = 'ios-workflow';

function readToken() {
  if (process.env.CODEMAGIC_API_TOKEN) return process.env.CODEMAGIC_API_TOKEN.trim();
  const f = path.join(root, '.codemagic-token');
  if (fs.existsSync(f)) return fs.readFileSync(f, 'utf8').trim();
  return null;
}

function request(method, url, headers, body) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const data = body ? JSON.stringify(body) : null;
    const opts = {
      hostname: u.hostname,
      path: u.pathname + u.search,
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {}),
        ...headers,
      },
    };
    const req = https.request(opts, (res) => {
      let raw = '';
      res.on('data', (c) => (raw += c));
      res.on('end', () => resolve({ status: res.statusCode, body: raw }));
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function triggerWebhook(appId, commitSha) {
  const payload = {
    ref: `refs/heads/${branch}`,
    repository: {
      name: 'wisdomapp',
      full_name: 'raihom-netizen/wisdomapp',
      html_url: 'https://github.com/raihom-netizen/wisdomapp',
      default_branch: 'main',
      private: true,
    },
    pusher: { name: 'WISDOMAPP-Deploy' },
    head_commit: {
      id: commitSha,
      message: 'chore(ios): trigger CodeMagic build [ci]',
      timestamp: new Date().toISOString(),
    },
  };
  const url = `https://api.codemagic.io/hooks/${appId}`;
  return request('POST', url, {}, payload);
}

async function listApps(token) {
  const r = await request('GET', 'https://api.codemagic.io/apps', { 'x-auth-token': token });
  if (r.status !== 200) throw new Error(`apps ${r.status}: ${r.body.slice(0, 200)}`);
  const j = JSON.parse(r.body);
  return j.applications || [];
}

async function createApp(token) {
  const r = await request('POST', 'https://api.codemagic.io/apps', { 'x-auth-token': token }, {
    repositoryUrl: repo,
  });
  if (r.status !== 200 && r.status !== 201) throw new Error(`create app ${r.status}: ${r.body.slice(0, 300)}`);
  const j = JSON.parse(r.body);
  return j._id || (j.application && j.application._id);
}

async function startBuild(token, appId) {
  const r = await request('POST', 'https://api.codemagic.io/builds', { 'x-auth-token': token }, {
    appId,
    workflowId,
    branch,
    environment: { groups: ['appstore_credentials', 'firebase_ipa_upload'] },
  });
  if (r.status !== 200 && r.status !== 201) throw new Error(`build ${r.status}: ${r.body.slice(0, 300)}`);
  return JSON.parse(r.body);
}

async function main() {
  const { execSync } = require('child_process');
  let commitSha = '0000000';
  try {
    commitSha = execSync('git rev-parse HEAD', { cwd: root, encoding: 'utf8' }).trim();
  } catch (_) {}

  console.log('=== Trigger CodeMagic iOS ===');
  console.log('Branch:', branch, '| Commit:', commitSha.slice(0, 8));

  const token = readToken();
  if (token) {
    try {
      const apps = await listApps(token);
      let appId = apps.find((a) => a.repositoryUrl && a.repositoryUrl.includes('wisdomapp') && a._id !== archivedAppId);
      appId = appId && appId._id;
      if (!appId) {
        console.log('Registrando app novo (wisdomapp archived)...');
        appId = await createApp(token);
        console.log('Novo app:', appId);
      } else {
        console.log('App ativo:', appId);
      }
      const build = await startBuild(token, appId);
      console.log('BUILD OK:', build.buildId || JSON.stringify(build));
      console.log(`https://codemagic.io/app/${appId}/build/${build.buildId || ''}`);
      return;
    } catch (e) {
      console.warn('API falhou:', e.message);
    }
  }

  console.log('Tentando webhook (app archived pode falhar)...');
  for (const id of [archivedAppId]) {
    const wh = await triggerWebhook(id, commitSha);
    console.log(`Webhook ${id}: HTTP ${wh.status}`, wh.body.slice(0, 120));
    if (wh.status >= 200 && wh.status < 300) {
      console.log('Webhook aceito. Veja Builds no CodeMagic.');
      return;
    }
  }

  console.error('');
  console.error('Nao foi possivel iniciar build automaticamente.');
  console.error('Cole API token em .codemagic-token (Codemagic > Account settings > API token)');
  console.error('Ou desarquive wisdomapp: Repository settings > Unarchive');
  process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
