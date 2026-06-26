/**
 * Bootstrap Firestore + Storage para WISDOMAPP (local — requer service account).
 * Preferir: .\tool\bootstrap_firestore.ps1 (chama Cloud Function apos deploy).
 */
const path = require("path");
const admin = require(path.join(__dirname, "..", "functions", "node_modules", "firebase-admin"));
const { runWisdomappFirestoreBootstrap } = require(path.join(__dirname, "..", "functions", "wisdomapp_firestore_bootstrap"));

if (!admin.apps.length) {
  admin.initializeApp({ storageBucket: "wisdomapp-b9e98.firebasestorage.app" });
}

const force = process.argv.includes("--force");

async function main() {
  console.log("=== Bootstrap WISDOMAPP (local Admin SDK) ===");
  console.log("force:", force);
  const results = await runWisdomappFirestoreBootstrap(admin.firestore(), admin, { force });
  console.log(JSON.stringify(results, null, 2));
  console.log("\nBootstrap concluido.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
