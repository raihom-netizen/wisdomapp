/**
 * Gera chave privada RSA 2048 em formato PEM para CERTIFICATE_PRIVATE_KEY no Codemagic.
 * O WISDOMAPP reutiliza o mesmo grupo appstore_credentials do Controle Total — só gere se ainda não tiver.
 * Uso: node scripts/generate_ios_certificate_key.js
 */
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const outDir = process.env.TEMPORARIOS || 'D:\\TEMPORARIOS';
const outFile = path.join(outDir, 'codemagic_ios_distribution_key.pem');

const { privateKey } = crypto.generateKeyPairSync('rsa', {
  modulusLength: 2048,
  privateKeyEncoding: { type: 'pkcs1', format: 'pem' },
  publicKeyEncoding: { type: 'spki', format: 'pem' },
});

if (!fs.existsSync(outDir)) {
  fs.mkdirSync(outDir, { recursive: true });
}
fs.writeFileSync(outFile, privateKey, 'utf8');

console.log('Chave salva em:', outFile);
console.log('');
console.log('WISDOMAPP usa o mesmo CERTIFICATE_PRIVATE_KEY do Controle Total (grupo appstore_credentials).');
console.log('Só cole esta chave se ainda não existir no Team do Codemagic.');
