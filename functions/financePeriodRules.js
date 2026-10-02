/**
 * Regras puras dos totais do período do Financeiro — as MESMAS do app
 * (porta do Controle Total), sem Firestore, para o `ctFinancePeriodTotals` e
 * para o teste offline (`teste_finance_period_rules.js`).
 *
 *  - data efetiva: effectiveDate › paidAt › date
 *    (app: `FinanceLineOpening.effectiveDateTimeFromMap`);
 *  - fora de Receitas/Despesas, mas dentro do saldo: pagamento de fatura,
 *    transferência própria e reserva/resgate de meta
 *    (app: `financeForaDosTotais`; CT: `FinancePeriodSummary.load`);
 *  - saldo por conta: só pago; cartão de crédito fora; despesa com
 *    `paidFromFinanceAccountId` sai da conta que pagou
 *    (app: `FinanceAccountBalanceUtils.netPaidByAccountEffectiveFromMaps`);
 *  - despesas pendentes: tira cartão (vai na fatura) e o que é fora dos
 *    totais (app: faixas de pendentes / `resumirPendentes`).
 */

"use strict";

function asJsDate(v) {
  if (!v) return null;
  if (v instanceof Date) return v;
  if (typeof v.toDate === "function") return v.toDate();
  return null;
}

/** effectiveDate › paidAt › date (igual ao app). */
function effectiveJsDate(x) {
  if (!x) return null;
  return asJsDate(x.effectiveDate) || asJsDate(x.paidAt) || asJsDate(x.date);
}

/**
 * Dinheiro mudando de lugar — não é receita nem despesa
 * (`financeForaDosTotais` do app; o WISDOMAPP não tem Finance Pro, então o
 * par de transferência do app (`transferPairId`) continua somando).
 */
function foraDosTotais(x) {
  if (!x) return false;
  return (
    x.faturaPagamento === true ||
    x.transferenciaPropria === true ||
    x.isTransfer === true ||
    x.goalReserve === true
  );
}

/** Receita +, despesa − (valor absoluto). */
function valorComSinal(x) {
  const v = Math.abs(Number(x && x.amount) || 0);
  return ((x && x.type) || "expense").toString() === "income" ? v : -v;
}

/** `FinanceAccount.isCreditCardProduct` (productType «card»; legado kind «card»). */
function isCreditCardAccountData(d) {
  if (!d) return false;
  const pt = ((d.productType || "") + "").trim();
  if (["checking", "savings", "card", "bank_and_card", "vault"].includes(pt)) {
    return pt === "card";
  }
  return ((d.kind || "bank") + "") === "card";
}

/**
 * Conta e valor que o lançamento PAGO move no saldo por conta
 * (`netPaidByAccountEffectiveFromMaps`, sem o filtro de data).
 */
function netPaidAccountSlot(x, creditCardIds) {
  const none = { accountId: null, delta: 0 };
  if (!x) return none;
  if ((x.status || "paid").toString() !== "paid") return none;
  const amount = Math.abs(Number(x.amount) || 0);
  if (!(amount > 0)) return none;
  const type = (x.type || "expense").toString();
  const accountId = ((x.financeAccountId || "") + "").trim();
  const paidFrom = ((x.paidFromFinanceAccountId || "") + "").trim();
  if (paidFrom && type === "expense" && !creditCardIds.has(paidFrom)) {
    return { accountId: paidFrom, delta: -amount };
  }
  if (!accountId || creditCardIds.has(accountId)) return none;
  return { accountId, delta: type === "income" ? amount : -amount };
}

function statusPasses(x, statusFilter) {
  const st = (x.status || "paid").toString();
  // «Todos» soma só o pago (regra antiga do servidor, mantida).
  if (statusFilter === "all" || statusFilter === "paid") return st === "paid";
  if (statusFilter === "pending") return st === "pending";
  return st === statusFilter;
}

/**
 * Soma o período. [items]: lançamentos (mapas) — pode ter repetidos por id
 * se vierem em `{ id, data }`; aqui recebe só os mapas já sem repetição.
 *
 * Devolve:
 *  - income / expense: SEM fatura, transferência própria e meta;
 *  - ajusteSaldo: líquido PAGO do que ficou fora (volta no saldo);
 *  - goalReserveNet: só a parte de meta (informativo);
 *  - periodByAccount: líquido pago por conta (cartão fora, paidFrom).
 */
function somarPeriodo(items, { start, end, statusFilter = "paid", typeFilter = "all", creditCardIds = new Set() }) {
  let income = 0;
  let expense = 0;
  let ajusteSaldo = 0;
  let goalReserveNet = 0;
  const periodByAccount = {};
  for (const x of items) {
    if (!x) continue;
    if (!statusPasses(x, statusFilter)) continue;
    const eff = effectiveJsDate(x);
    if (!eff || eff < start || eff > end) continue;
    const type = (x.type || "expense").toString();
    if (typeFilter === "income" && type !== "income") continue;
    if (typeFilter === "expense" && type !== "expense") continue;
    const amount = Math.abs(Number(x.amount) || 0);
    if (!Number.isFinite(amount)) continue;
    const paid = (x.status || "paid").toString() === "paid";
    if (foraDosTotais(x)) {
      if (paid) {
        ajusteSaldo += valorComSinal(x);
        if (x.goalReserve === true) goalReserveNet += valorComSinal(x);
      }
    } else if (type === "income") {
      income += amount;
    } else {
      expense += amount;
    }
    const slot = netPaidAccountSlot(x, creditCardIds);
    if (slot.accountId) {
      periodByAccount[slot.accountId] = (periodByAccount[slot.accountId] || 0) + slot.delta;
    }
  }
  return { income, expense, ajusteSaldo, goalReserveNet, periodByAccount };
}

/**
 * Despesa pendente que conta no aviso «N pendente(s)»: vencimento (`date`) no
 * período, fora cartão de crédito (vai na fatura) e fora pagamento de
 * fatura/transferência/meta.
 */
function contaComoPendente(x, { start, end, creditCardIds = new Set() }) {
  if (!x) return false;
  if ((x.status || "paid").toString() !== "pending") return false;
  if ((x.type || "expense").toString() !== "expense") return false;
  if (foraDosTotais(x)) return false;
  const acc = ((x.financeAccountId || "") + "").trim();
  if (acc && creditCardIds.has(acc)) return false;
  const dt = asJsDate(x.date);
  if (!dt || dt < start || dt > end) return false;
  return true;
}

module.exports = {
  asJsDate,
  effectiveJsDate,
  foraDosTotais,
  valorComSinal,
  isCreditCardAccountData,
  netPaidAccountSlot,
  somarPeriodo,
  contaComoPendente,
};
