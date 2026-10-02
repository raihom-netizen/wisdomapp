/**
 * Teste offline do «Despertar» POR ITEM — Node puro, sem rede.
 *
 *   node teste_despertar_item.js
 *
 * O que não pode quebrar:
 *   (a) item sem o campo (antigo / bot) → DESLIGADO, mesmo com o módulo
 *       ligado (padrão desativado) — Contas também;
 *   (b) ativo=false desliga o despertador mesmo com o módulo ligado;
 *   (c) ativo=true liga mesmo com o módulo desligado, com o toque escolhido,
 *       o longo do módulo ou o padrão; «só vibrar» sem som; vezes/intervalo
 *       do módulo, ou 3 × 3 min quando o módulo não tem escolha;
 *   (d) plantão sem campo herda o pré-cadastro recorrente (casamento forte);
 *   (e) alarme «no horário» respeita o som/vibrar do despertar do item.
 */

"use strict";

const assert = require("assert");
const item = require("./agenda_despertar_item");
const soneca = require("./agenda_soneca");
const despertador = require("./agenda_despertador");

const config = {
  soneca: soneca.parseSonecaConfig({
    sonecaAtiva: true,
    sonecaModulos: { escala: { ativa: true, vezes: 5, intervaloMin: 3 } },
  }),
  sons: { all: "", escala: "sino_duplo", compromisso: "longo_sirene", audiencia: "", financeiro: "" },
  modos: {},
};

// (a)
assert.strictEqual(item.despertarDoItem({}), null);
assert.strictEqual(item.despertarDoItem({ despertar: { modo: "som" } }), null);
assert.strictEqual(soneca.sonecaAtivaPara(config, "escala"), true, "módulo ligado");
const cfgSemCampo = item.configComDespertar(config, "escala", null);
assert.strictEqual(soneca.sonecaAtivaPara(cfgSemCampo, "escala"), false, "sem campo = desligado");
assert.strictEqual(soneca.sonecaAtivaPara(config, "escala"), true, "config original não muda");
assert.strictEqual(item.somDoDespertar(config, "escala", null), null);
assert.strictEqual(
  soneca.sonecaAtivaPara(item.configComDespertar(config, "compromisso", item.despertarEfetivo({ title: "X" })), "compromisso"),
  false,
);
// Contas: o lançamento decide; só pendente desperta.
const cfgContas = {
  ...config,
  soneca: soneca.parseSonecaConfig({ sonecaAtiva: true, sonecaModulos: { financeiro: { ativa: true } } }),
};
assert.strictEqual(soneca.sonecaAtivaPara(item.configComDespertar(cfgContas, "financeiro", null), "financeiro"), false);
const contaOn = { status: "pending", despertar: { ativo: true, modo: "som", som: "" } };
const dConta = item.despertarEfetivo(contaOn, { sourceType: "transaction" });
assert.deepStrictEqual(dConta, { ativo: true, modo: "som", som: "" });
assert.strictEqual(soneca.sonecaAtivaPara(item.configComDespertar(cfgContas, "financeiro", dConta), "financeiro"), true);
assert.strictEqual(item.despertarEfetivo({ ...contaOn, status: "paid" }, { sourceType: "transaction" }), null, "paga não desperta");

// (b)
const off = item.despertarDoItem({ despertar: { ativo: false, modo: "som", som: "" } });
const cfgOff = item.configComDespertar(config, "escala", off);
assert.strictEqual(soneca.sonecaAtivaPara(cfgOff, "escala"), false);
assert.strictEqual(soneca.sonecaAtivaPara(config, "escala"), true, "config original não muda");
assert.strictEqual(item.somDoDespertar(config, "escala", off), null);

// (c)
const on = item.despertarDoItem({ despertar: { ativo: true, modo: "som", som: "extra_sirene" } });
const cfgOn = item.configComDespertar(config, "compromisso", on);
assert.strictEqual(soneca.sonecaAtivaPara(cfgOn, "compromisso"), true);
// Módulo Compromissos sem vezes/intervalo escolhidos → 3 × 3 min.
assert.strictEqual(cfgOn.soneca.compromisso.vezes, 3);
assert.strictEqual(cfgOn.soneca.compromisso.intervaloMin, 3);
// Módulo Escalas com 5 × 3 escolhidos → vale a escolha, mesmo com o módulo desligado.
const cfgEscOff = {
  ...config,
  soneca: soneca.parseSonecaConfig({ sonecaAtiva: false, sonecaModulos: { escala: { ativa: false, vezes: 5, intervaloMin: 5 } } }),
};
const cfgEscOn = item.configComDespertar(cfgEscOff, "escala", on);
assert.strictEqual(soneca.sonecaAtivaPara(cfgEscOff, "escala"), false);
assert.strictEqual(soneca.sonecaAtivaPara(cfgEscOn, "escala"), true);
assert.strictEqual(cfgEscOn.soneca.escala.vezes, 5);
assert.strictEqual(cfgEscOn.soneca.escala.intervaloMin, 5);
assert.deepStrictEqual(item.somDoDespertar(config, "compromisso", on), { modo: "som", soundId: "extra_sirene" });
const onPadrao = item.despertarDoItem({ despertar: { ativo: true, modo: "som", som: "" } });
assert.deepStrictEqual(item.somDoDespertar(config, "compromisso", onPadrao), { modo: "som", soundId: "longo_sirene" });
assert.deepStrictEqual(item.somDoDespertar(config, "escala", onPadrao), { modo: "som", soundId: item.SOM_PADRAO });
const vib = item.despertarDoItem({ despertar: { ativo: true, modo: "vibrar", som: "extra_sirene" } });
assert.deepStrictEqual(item.somDoDespertar(config, "audiencia", vib), { modo: "vibrar", soundId: "" });
assert.strictEqual(item.despertarDoItem({ despertar: { ativo: true, modo: "x", som: "../etc" } }).som, "");

// (d)
const locais = [
  { name: "PLANTÃO", abbreviation: "PLA", despertar: { ativo: false, modo: "som", som: "" } },
  { name: "PLANTÃO ORDINÁRIO", abbreviation: "PORD", despertar: { ativo: true, modo: "vibrar", som: "" } },
  { name: "CASE", abbreviation: "CASE" },
];
const plantao = { label: "PLANTÃO ORDINÁRIO 08:00 ÀS 20:00 12 HORAS", abbreviation: "PORD" };
assert.deepStrictEqual(
  item.despertarEfetivo(plantao, { sourceType: "scale", locations: locais }),
  { ativo: true, modo: "vibrar", som: "" },
);
assert.strictEqual(item.despertarEfetivo({ label: "CASE 07:00 às 19:00", abbreviation: "CASE" }, { sourceType: "scale", locations: locais }), null);
assert.strictEqual(item.despertarEfetivo({ label: "PLANTÃO EXTRA", abbreviation: "PEX" }, { sourceType: "scale", locations: locais }), null, "contenção não casa");
// O campo do próprio plantão vence o pré-cadastro.
assert.deepStrictEqual(
  item.despertarEfetivo({ ...plantao, despertar: { ativo: false, modo: "som", som: "" } }, { sourceType: "scale", locations: locais }),
  { ativo: false, modo: "som", som: "" },
);
// Compromisso (reminder) não procura pré-cadastro.
assert.strictEqual(item.despertarEfetivo(plantao, { sourceType: "reminder", locations: locais }), null);

// (e)
assert.deepStrictEqual(despertador.somDoAlarme(config, { despertar: { ativo: true, modo: "vibrar" } }), { modo: "vibrar", soundId: "" });
assert.deepStrictEqual(despertador.somDoAlarme(config, { despertar: { ativo: true, modo: "som", som: "extra_urgente" } }), { modo: "som", soundId: "extra_urgente" });
assert.deepStrictEqual(despertador.somDoAlarme(config, {}), { modo: "som", soundId: "longo_sirene" });

console.log("teste_despertar_item: OK");
