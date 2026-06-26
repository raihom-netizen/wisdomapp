/**
 * Define role=gestor para e-mails de gestor de conteúdo.
 * Uso: node scripts/set-gestor-role.js
 * Requer GOOGLE_APPLICATION_CREDENTIALS ou firebase login (Admin SDK via application default).
 */
const admin = require('firebase-admin');

const GESTOR_EMAILS = ['tarleypmgo@gmail.com'];

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: process.env.GCLOUD_PROJECT || 'wisdomapp-b9e98',
    });
  }
  const auth = admin.auth();
  const db = admin.firestore();

  for (const email of GESTOR_EMAILS) {
    let user;
    try {
      user = await auth.getUserByEmail(email);
    } catch (e) {
      console.warn(`[skip] ${email} — não encontrado no Auth: ${e.message}`);
      continue;
    }
    await db.collection('users').doc(user.uid).set(
      {
        email,
        role: 'gestor',
        adminLevel: 'Editor',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    console.log(`OK gestor: ${email} (uid ${user.uid})`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
