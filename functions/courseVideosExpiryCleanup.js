"use strict";

/**
 * Diário (04:00 Brasília): apaga documentos `course_videos` cuja validade
 * expirou no dia anterior (validityMode=expires + expiresAt).
 */
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const TZ_BRASILIA = "America/Sao_Paulo";

function brasiliaDateKey(ms) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ_BRASILIA,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(ms));
}

function expiresDateKey(data) {
  const exp = data.expiresAt;
  if (!exp) return null;
  let ms;
  if (typeof exp.toMillis === "function") ms = exp.toMillis();
  else if (exp.seconds != null) ms = exp.seconds * 1000;
  else return null;
  return brasiliaDateKey(ms);
}

function isPermanent(data) {
  const mode = (data.validityMode || "permanent").toString().trim();
  if (mode === "permanent") return true;
  return !data.expiresAt;
}

function shouldDelete(data, todayKey) {
  if (isPermanent(data)) return false;
  const expKey = expiresDateKey(data);
  if (!expKey) return false;
  return todayKey > expKey;
}

/** Caminho no Storage a partir de uma URL de download do Firebase (`/o/<path>`). */
function storagePathFromUrl(raw) {
  const url = (raw || "").toString().trim();
  if (!url) return null;
  if (url.startsWith("gs://")) {
    const rest = url.slice(5);
    const i = rest.indexOf("/");
    return i > 0 ? rest.slice(i + 1) : null;
  }
  if (!/firebasestorage\.googleapis\.com|\.firebasestorage\.app/.test(url)) {
    return null;
  }
  const m = url.match(/\/o\/([^?#]+)/);
  if (!m) return null;
  try {
    return decodeURIComponent(m[1]);
  } catch (_) {
    return null;
  }
}

function addPath(out, raw) {
  const v = (raw || "").toString().trim();
  if (!v) return;
  if (/^(https?:|gs:)/i.test(v)) {
    const p = storagePathFromUrl(v);
    if (p) out.add(p);
    return;
  }
  out.add(v.replace(/^\/+/, ""));
}

/**
 * Todos os arquivos do curso no Storage: vídeos (`mp4Urls[]` — formato que o
 * app grava —, `videoFiles[]` legado, `mp4StoragePath`), fotos e capa quando
 * a capa é do nosso Storage (URL do YouTube é ignorada).
 */
function collectStoragePaths(data) {
  const out = new Set();
  const singles = [
    "coverStoragePath",
    "imageStoragePath",
    "storagePath",
    "mp4StoragePath",
    "videoStoragePath",
  ];
  for (const k of singles) addPath(out, data[k]);
  for (const k of ["imageStoragePaths", "photoStoragePaths"]) {
    const arr = data[k];
    if (!Array.isArray(arr)) continue;
    for (const p of arr) addPath(out, p);
  }
  // URLs soltas (capa/vídeo) só entram se forem do Firebase Storage.
  for (const k of ["mp4Url", "thumbnailUrl", "coverUrl", "imageUrl"]) {
    const p = storagePathFromUrl(data[k]);
    if (p) out.add(p);
  }
  const imageUrls = data.imageUrls;
  if (Array.isArray(imageUrls)) {
    for (const u of imageUrls) {
      const p = storagePathFromUrl(u);
      if (p) out.add(p);
    }
  }
  for (const k of ["mp4Urls", "videoFiles"]) {
    const arr = data[k];
    if (!Array.isArray(arr)) continue;
    for (const item of arr) {
      if (!item) continue;
      if (typeof item === "string") {
        addPath(out, item);
        continue;
      }
      if (item.storagePath) addPath(out, item.storagePath);
      else if (item.url) {
        const p = storagePathFromUrl(item.url);
        if (p) out.add(p);
      }
    }
  }
  return [...out];
}

async function deleteStoragePaths(bucket, paths) {
  for (const path of paths) {
    try {
      await bucket.file(path).delete({ ignoreNotFound: true });
    } catch (e) {
      console.warn("courseVideosExpiryCleanup storage:", path, e && e.message);
    }
  }
}

/** Pasta padrão do curso (`wisdomapp/course_videos/{id}/`) — pega sobras. */
async function deleteCourseFolder(bucket, docId) {
  if (!docId) return;
  try {
    await bucket.deleteFiles({
      prefix: `wisdomapp/course_videos/${docId}/`,
      force: true,
    });
  } catch (e) {
    console.warn("courseVideosExpiryCleanup folder:", docId, e && e.message);
  }
}

const SWEEP_PAGE = 500;
const SWEEP_MAX_SCAN = 3000;
const SWEEP_MAX_DELETE = 1500;
const SWEEP_CURSOR_DOC = "system_jobs/courseProgressOrphanSweep";

/**
 * Remove `users/{uid}/course_progress/{courseId}` cujo curso não existe mais.
 * Varre em páginas (com limite por execução) e guarda o cursor para continuar
 * no dia seguinte; ao chegar ao fim recomeça do início.
 */
async function sweepOrphanProgress(db, removedIds) {
  const exists = new Map();
  for (const id of removedIds) exists.set(id, false);
  const cursorRef = db.doc(SWEEP_CURSOR_DOC);
  let cursor = null;
  try {
    const c = await cursorRef.get();
    cursor = c.exists ? (c.data().lastPath || null) : null;
  } catch (_) {}

  let scanned = 0;
  let deleted = 0;
  let reachedEnd = false;
  while (scanned < SWEEP_MAX_SCAN && deleted < SWEEP_MAX_DELETE) {
    let q = db
      .collectionGroup("course_progress")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(SWEEP_PAGE);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) {
      reachedEnd = true;
      break;
    }
    const batch = db.batch();
    let inBatch = 0;
    for (const doc of snap.docs) {
      const courseId = doc.id;
      if (!exists.has(courseId)) {
        const c = await db.collection("course_videos").doc(courseId).get();
        exists.set(courseId, c.exists);
      }
      if (!exists.get(courseId) && deleted < SWEEP_MAX_DELETE) {
        batch.delete(doc.ref);
        inBatch++;
        deleted++;
      }
    }
    if (inBatch > 0) await batch.commit();
    scanned += snap.size;
    cursor = snap.docs[snap.docs.length - 1].ref.path;
    if (snap.size < SWEEP_PAGE) {
      reachedEnd = true;
      break;
    }
  }
  try {
    await cursorRef.set(
      {
        lastPath: reachedEnd ? null : cursor,
        lastRunAt: admin.firestore.FieldValue.serverTimestamp(),
        lastScanned: scanned,
        lastDeleted: deleted,
      },
      { merge: true },
    );
  } catch (_) {}
  return { scanned, deleted };
}

const courseVideosExpiryCleanupScheduled = onSchedule(
  {
    schedule: "0 4 * * *",
    timeZone: TZ_BRASILIA,
    region: "us-central1",
    timeoutSeconds: 540,
  },
  async () => {
    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const todayKey = brasiliaDateKey(Date.now());
    // Só os que têm validade — não lê a coleção inteira.
    const snap = await db
      .collection("course_videos")
      .where("validityMode", "==", "expires")
      .get();
    let removed = 0;
    const removedIds = [];
    for (const doc of snap.docs) {
      const data = doc.data() || {};
      if (!shouldDelete(data, todayKey)) continue;
      const paths = collectStoragePaths(data);
      await deleteStoragePaths(bucket, paths);
      await deleteCourseFolder(bucket, doc.id);
      await doc.ref.delete();
      removedIds.push(doc.id);
      removed++;
      console.log("courseVideosExpiryCleanup removed", doc.id, "files=", paths.length);
    }
    console.log("courseVideosExpiryCleanup done, removed=", removed);
    try {
      const r = await sweepOrphanProgress(db, removedIds);
      console.log("courseVideosExpiryCleanup progress sweep", r);
    } catch (e) {
      console.warn("courseVideosExpiryCleanup progress sweep failed:", e && e.message);
    }
  },
);

module.exports = {
  courseVideosExpiryCleanupScheduled,
  // Exportados para teste.
  collectStoragePaths,
  storagePathFromUrl,
};
