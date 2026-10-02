/**
 * Teste offline do resumo diário — Node puro, sem rede.
 *
 *   node teste_agenda_daily_digest.js
 *
 * O que não pode quebrar:
 *   (a) só lê o dia-alvo (consulta por data, não a coleção inteira);
 *   (b) modelo da série anual (isYearlyRepeatTemplate) não entra — só a
 *       ocorrência do ano (evita o anual em dobro);
 *   (c) espelhos da agenda/folga nas escalas continuam fora.
 */

"use strict";

const assert = require("assert");
const admin = require("firebase-admin");
const digest = require("./agenda_daily_digest");

function ts(date) {
  return admin.firestore.Timestamp.fromDate(date);
}

/** Firestore de mentira: só o que o resumo usa (where por data + get). */
function fakeDb(data) {
  const queries = [];
  function query(path, filters) {
    return {
      where(field, op, value) {
        return query(path, filters.concat([{ field, op, value }]));
      },
      async get() {
        queries.push({ path, filters });
        const docs = (data[path] || [])
          .filter((row) =>
            filters.every((f) => {
              const v = row.data[f.field];
              if (!v || typeof v.toMillis !== "function") return false;
              const a = v.toMillis();
              const b = f.value.toMillis();
              if (f.op === ">=") return a >= b;
              if (f.op === "<=") return a <= b;
              throw new Error(`op não suportado: ${f.op}`);
            }),
          )
          .map((row) => ({ id: row.id, data: () => row.data }));
        return { docs, empty: docs.length === 0, size: docs.length };
      },
    };
  }
  return {
    queries,
    collection(c1) {
      return {
        doc(id) {
          return {
            collection(c2) {
              return query(`${c1}/${id}/${c2}`, []);
            },
          };
        },
      };
    },
  };
}

(async () => {
  // Dia-alvo 10/03/2027 (Brasília = UTC-3 → meia-noite local = 03:00 UTC).
  const alvo = new Date(Date.UTC(2027, 2, 10, 15, 0, 0));
  const bounds = digest.dayBoundsBrasilia(alvo);
  const meiaNoite = new Date(Date.UTC(2027, 2, 10, 3, 0, 0));
  const ontem = new Date(Date.UTC(2027, 2, 9, 3, 0, 0));

  const db = fakeDb({
    "users/u1/reminders": [
      { id: "tplA", data: { title: "Casamento", time: "09:00", date: ts(meiaNoite), repeatYearly: true, isYearlyRepeatTemplate: true } },
      { id: "tplA_y2027", data: { title: "Casamento", time: "09:00", date: ts(meiaNoite), repeatYearly: true, yearlyRepeatTemplateId: "tplA" } },
      { id: "tplB", data: { title: "Antigo", time: "10:00", date: ts(meiaNoite), source: "yearly_repeat_template" } },
      { id: "r1", data: { title: "Dentista", time: "14:30", date: ts(meiaNoite) } },
      { id: "r0", data: { title: "Ontem", time: "08:00", date: ts(ontem) } },
      { id: "aud", data: { title: "Audiência X", type: "audiencia", time: "11:00", date: ts(meiaNoite) } },
    ],
    "users/u1/scales": [
      { id: "s1", data: { label: "Plantão", start: "07:00", date: ts(meiaNoite) } },
      { id: "agenda_r1", data: { label: "Dentista", isAgendaMirror: true, start: "14:30", date: ts(meiaNoite) } },
      { id: "s0", data: { label: "Plantão ontem", start: "07:00", date: ts(ontem) } },
    ],
  });

  const items = await digest.collectTomorrowAgendaItems(db, "u1", bounds);

  // (b) anual uma vez só, comuns entram
  assert.deepStrictEqual(
    items.compromisso.map((i) => i.label),
    ["Casamento", "Dentista"],
  );
  assert.deepStrictEqual(items.audiencia.map((i) => i.label), ["Audiência X"]);
  // (c) espelho fora, (a) ontem fora
  assert.deepStrictEqual(items.escala.map((i) => i.label), ["Plantão"]);

  // (a) as duas leituras vieram com filtro de data
  assert.strictEqual(db.queries.length, 2);
  for (const q of db.queries) {
    assert.deepStrictEqual(q.filters.map((f) => f.op), [">=", "<="]);
    assert.strictEqual(q.filters[0].field, "date");
  }

  assert.strictEqual(digest.isYearlyRepeatTemplateDoc({ isYearlyRepeatTemplate: true }), true);
  assert.strictEqual(digest.isYearlyRepeatTemplateDoc({ repeatYearly: true }), false);

  console.log("OK teste_agenda_daily_digest");
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
