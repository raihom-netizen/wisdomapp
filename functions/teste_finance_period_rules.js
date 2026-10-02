/**
 * Teste offline dos totais do período (ctFinancePeriodTotals) e dos buckets
 * por conta (versão 4) — Node puro, sem rede.
 *
 *   node teste_finance_period_rules.js
 *
 * Regra (a mesma do app e do Controle Total):
 *   (a) período pela data efetiva (effectiveDate › paidAt › date);
 *   (b) pagamento de fatura, transferência própria e meta fora de
 *       receitas/despesas, mas dentro do saldo (ajuste);
 *   (c) saldo por conta: cartão fora, despesa com paidFrom sai de quem pagou;
 *   (d) pendentes: sem cartão e sem fora-dos-totais;
 *   (e) bucket por conta: paidFrom vai para a conta que pagou; total igual.
 */

"use strict";

process.env.TZ = "America/Sao_Paulo";

const assert = require("assert");
const admin = require("firebase-admin");
const regras = require("./financePeriodRules");
const buckets = require("./financeMonthBuckets");

const ts = (d) => admin.firestore.Timestamp.fromDate(d);
let ok = 0;
function caso(nome, fn) {
  fn();
  ok += 1;
  console.log(`  ok — ${nome}`);
}

const start = new Date(2026, 9, 1, 0, 0, 0, 0);
const end = new Date(2026, 9, 31, 23, 59, 59, 999);
const cartoes = new Set(["nubank_cartao"]);

caso("(a) compra com date 28/09 paga 02/10 entra em outubro", () => {
  const x = {
    type: "expense",
    amount: 80,
    status: "paid",
    financeAccountId: "itau",
    date: ts(new Date(2026, 8, 28)),
    paidAt: ts(new Date(2026, 9, 2)),
    effectiveDate: ts(new Date(2026, 9, 2)),
  };
  const r = regras.somarPeriodo([x], { start, end, creditCardIds: cartoes });
  assert.strictEqual(r.expense, 80);
  assert.deepStrictEqual(r.periodByAccount, { itau: -80 });
});

caso("(a) lançado em outubro mas pago em novembro NÃO entra em outubro", () => {
  const x = {
    type: "expense",
    amount: 50,
    status: "paid",
    financeAccountId: "itau",
    date: ts(new Date(2026, 9, 30)),
    effectiveDate: ts(new Date(2026, 10, 3)),
  };
  const r = regras.somarPeriodo([x], { start, end, creditCardIds: cartoes });
  assert.strictEqual(r.expense, 0);
});

caso("(b) fatura/transferência/meta fora de receitas e despesas; saldo igual", () => {
  const d = ts(new Date(2026, 9, 10));
  const itens = [
    { type: "income", amount: 1000, status: "paid", financeAccountId: "itau", date: d },
    { type: "expense", amount: 300, status: "paid", financeAccountId: "itau", date: d },
    { type: "expense", amount: 500, status: "paid", financeAccountId: "itau", date: d, faturaPagamento: true },
    { type: "expense", amount: 200, status: "paid", financeAccountId: "itau", date: d, goalReserve: true },
    { type: "expense", amount: 40, status: "paid", financeAccountId: "itau", date: d, transferenciaPropria: true },
    { type: "income", amount: 40, status: "paid", financeAccountId: "inter", date: d, isTransfer: true },
  ];
  const r = regras.somarPeriodo(itens, { start, end, creditCardIds: cartoes });
  assert.strictEqual(r.income, 1000);
  assert.strictEqual(r.expense, 300);
  assert.strictEqual(r.ajusteSaldo, -700);
  assert.strictEqual(r.goalReserveNet, -200);
  // saldo = 1000 − 300 − 700 = 0 = soma de tudo com sinal (1000−300−500−200−40+40)
  assert.strictEqual(r.income - r.expense + r.ajusteSaldo, 0);
  assert.deepStrictEqual(r.periodByAccount, { itau: -40, inter: 40 });
});

caso("(c) cartão fora do saldo por conta; paidFrom debita o banco", () => {
  const d = ts(new Date(2026, 9, 12));
  const itens = [
    // compra no cartão ainda sem pagar: nada
    { type: "expense", amount: 90, status: "pending", financeAccountId: "nubank_cartao", date: d },
    // compra no cartão quitada pela fatura com o Itaú
    { type: "expense", amount: 300, status: "paid", financeAccountId: "nubank_cartao", paidFromFinanceAccountId: "itau", date: d },
    // compra no cartão quitada sem banco: entra na despesa, mas em conta nenhuma
    { type: "expense", amount: 20, status: "paid", financeAccountId: "nubank_cartao", date: d },
  ];
  const r = regras.somarPeriodo(itens, { start, end, creditCardIds: cartoes });
  assert.strictEqual(r.expense, 320);
  assert.deepStrictEqual(r.periodByAccount, { itau: -300 });
});

caso("status «todos» soma só o pago; filtro de tipo respeitado", () => {
  const d = ts(new Date(2026, 9, 5));
  const itens = [
    { type: "income", amount: 1000, status: "paid", date: d },
    { type: "income", amount: 400, status: "pending", date: d },
    { type: "expense", amount: 60, status: "paid", date: d },
  ];
  const all = regras.somarPeriodo(itens, { start, end, statusFilter: "all" });
  assert.strictEqual(all.income, 1000);
  const soRec = regras.somarPeriodo(itens, { start, end, typeFilter: "income" });
  assert.strictEqual(soRec.income, 1000);
  assert.strictEqual(soRec.expense, 0);
  const pend = regras.somarPeriodo(itens, { start, end, statusFilter: "pending" });
  assert.strictEqual(pend.income, 400);
  assert.deepStrictEqual(pend.periodByAccount, {});
});

caso("(d) pendentes: sem cartão e sem pagamento de fatura", () => {
  const d = new Date(2026, 9, 20);
  const itens = [
    { type: "expense", amount: 10, status: "pending", financeAccountId: "itau", date: ts(d) },
    { type: "expense", amount: 10, status: "pending", financeAccountId: "nubank_cartao", date: ts(d) },
    { type: "expense", amount: 10, status: "pending", financeAccountId: "itau", date: ts(d), faturaPagamento: true },
    { type: "expense", amount: 10, status: "pending", date: ts(new Date(2026, 10, 2)) },
  ];
  const n = itens.filter((x) => regras.contaComoPendente(x, { start, end, creditCardIds: cartoes })).length;
  assert.strictEqual(n, 1);
});

caso("cartão: productType card (e legado kind card); conta+cartão não", () => {
  assert.strictEqual(regras.isCreditCardAccountData({ productType: "card" }), true);
  assert.strictEqual(regras.isCreditCardAccountData({ productType: "bank_and_card" }), false);
  assert.strictEqual(regras.isCreditCardAccountData({ productType: "checking" }), false);
  assert.strictEqual(regras.isCreditCardAccountData({ kind: "card" }), true);
  assert.strictEqual(regras.isCreditCardAccountData({}), false);
});

caso("(e) bucket por conta v4: paidFrom vai para quem pagou; total igual", () => {
  const compra = {
    type: "expense",
    amount: 300,
    status: "paid",
    financeAccountId: "nubank_cartao",
    paidFromFinanceAccountId: "itau",
    date: ts(new Date(2026, 8, 10)),
  };
  assert.deepStrictEqual(buckets.accountBucketDelta(compra), { accountId: "itau", delta: -300 });
  assert.strictEqual(buckets.openingContribution(compra), -300);
  const receita = { type: "income", amount: 1000, status: "paid", financeAccountId: "itau" };
  assert.deepStrictEqual(buckets.accountBucketDelta(receita), { accountId: "itau", delta: 1000 });
  assert.deepStrictEqual(buckets.accountBucketDelta({ ...receita, status: "pending" }), { accountId: null, delta: 0 });
  assert.deepStrictEqual(buckets.accountBucketDelta({ type: "expense", amount: 5 }), { accountId: null, delta: 0 });
  assert.strictEqual(buckets.OPENING_BUCKETS_VERSION, 4);
});

console.log(`\n${ok} casos ok`);
