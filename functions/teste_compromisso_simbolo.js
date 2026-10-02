/**
 * Teste offline: emoji do compromisso (`commitmentSymbol`) no aviso push.
 *
 *   node teste_compromisso_simbolo.js
 *
 * (a) `emoji:🎂` entra no título e na linha do compromisso;
 * (b) `icon:*` (ícone do app) e sem campo → aviso igual ao de antes.
 */

"use strict";

const assert = require("assert");
const t = require("./agenda_message_templates");

const ev = new Date(Date.UTC(2027, 2, 10, 12, 0));
const now = new Date(Date.UTC(2027, 2, 10, 11, 0));

const comEmoji = t.buildPushFromReminder(
  { title: "Aniversário Ana", time: "09:00", commitmentSymbol: "emoji:🎂" },
  ev, 60, "Rai", now,
);
assert.ok(comEmoji.title.includes("Compromisso: 🎂 Aniversário Ana"), comEmoji.title);
assert.ok(comEmoji.body.includes("🎂 Aniversário Ana"), comEmoji.body);
assert.ok(!comEmoji.body.includes("📝 Aniversário Ana"), comEmoji.body);

const icone = t.buildPushFromReminder(
  { title: "Dentista", time: "09:00", commitmentSymbol: "icon:medical" },
  ev, 60, "Rai", now,
);
const semCampo = t.buildPushFromReminder(
  { title: "Dentista", time: "09:00" },
  ev, 60, "Rai", now,
);
assert.strictEqual(icone.title, semCampo.title);
assert.strictEqual(icone.body, semCampo.body);
assert.ok(semCampo.body.includes("📝 Dentista"), semCampo.body);

console.log("OK teste_compromisso_simbolo");
