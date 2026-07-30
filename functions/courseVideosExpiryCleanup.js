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

function collectStoragePaths(data) {
  const out = new Set();
  const singles = [
    "coverStoragePath",
    "imageStoragePath",
    "storagePath",
    "mp4StoragePath",
    "videoStoragePath",
  ];
  for (const k of singles) {
    const v = (data[k] || "").toString().trim();
    if (v) out.add(v);
  }
  for (const k of ["imageStoragePaths", "photoStoragePaths"]) {
    const arr = data[k];
    if (!Array.isArray(arr)) continue;
    for (const p of arr) {
      const v = (p || "").toString().trim();
      if (v) out.add(v);
    }
  }
  const videos = data.videoFiles;
  if (Array.isArray(videos)) {
    for (const item of videos) {
      if (item && item.storagePath) {
        const v = item.storagePath.toString().trim();
        if (v) out.add(v);
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

const courseVideosExpiryCleanupScheduled = onSchedule(
  {
    schedule: "0 4 * * *",
    timeZone: TZ_BRASILIA,
    region: "us-central1",
  },
  async () => {
    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const todayKey = brasiliaDateKey(Date.now());
    const snap = await db.collection("course_videos").get();
    let removed = 0;
    for (const doc of snap.docs) {
      const data = doc.data() || {};
      if (!shouldDelete(data, todayKey)) continue;
      const paths = collectStoragePaths(data);
      await deleteStoragePaths(bucket, paths);
      await doc.ref.delete();
      removed++;
      console.log("courseVideosExpiryCleanup removed", doc.id);
    }
    console.log("courseVideosExpiryCleanup done, removed=", removed);
  },
);

module.exports = { courseVideosExpiryCleanupScheduled };
