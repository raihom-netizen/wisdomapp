/**
 * PDF financeiro «Extrato Super Premium» no servidor (PDFKit) — alinhado ao app
 * (faixa azul, título, resumo 4 colunas, tabela Data / Descrição / Entrada / Saída / Saldo).
 */

const HEADER_BLUE = "#1e3a8a";
const TABLE_HEAD_BLUE = "#1d4ed8";
const MUTED = "#4b5563";
const TEXT = "#111827";
const BOX_BG = "#f3f4f6";
const BOX_BORDER = "#d1d5db";

function _clampStr(s, max) {
  const t = (s || "").toString().replace(/\s+/g, " ").trim();
  if (t.length <= max) return t;
  return `${t.slice(0, Math.max(0, max - 1))}...`;
}

function _fmtMoneyBr(v) {
  const n = Number(v || 0);
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(Number.isFinite(n) ? n : 0);
}

/**
 * @param {number} saldoAbertura
 * @param {Array<{ data: string, tipo: string, valor: number, cat: string, desc: string }>} rowsSortedAsc
 */
function buildExtratoLinhas(saldoAbertura, rowsSortedAsc) {
  const linhas = [];
  let saldo = Number(saldoAbertura) || 0;
  if (Math.abs(saldo) > 0.0001) {
    linhas.push({
      data: "-",
      desc: "Saldo de abertura",
      ent: "",
      sai: "",
      saldo: _fmtMoneyBr(saldo),
    });
  }
  for (const r of rowsSortedAsc) {
    const isInc = (r.tipo || "").toString() === "income";
    const abs = Math.abs(Number(r.valor) || 0);
    const desc = _clampStr(`${r.cat || "Sem categoria"}${r.desc ? " - " + r.desc : ""}`, 88);
    if (isInc) {
      saldo += abs;
      linhas.push({
        data: _clampStr(r.data, 12),
        desc,
        ent: _fmtMoneyBr(abs),
        sai: "",
        saldo: _fmtMoneyBr(saldo),
      });
    } else {
      saldo -= abs;
      linhas.push({
        data: _clampStr(r.data, 12),
        desc,
        ent: "",
        sai: _fmtMoneyBr(abs),
        saldo: _fmtMoneyBr(saldo),
      });
    }
  }
  return { linhas, saldoFinal: saldo };
}

/**
 * Desenha o PDF completo; o caller faz doc.end() após retorno (síncrono).
 * @param {import('pdfkit').PDFDocument} doc
 */
function drawFinanceSuperExtrato(doc, opts) {
  const {
    nomeUsuario,
    conta,
    periodo,
    saldoAbertura,
    totalReceitas,
    totalDespesas,
    linhas,
  } = opts;

  const saldoPeriodo = totalReceitas - totalDespesas;
  const saldoFinal = saldoAbertura + saldoPeriodo;
  const margin = 22;
  const pageW = 595;
  const innerW = pageW - margin * 2;
  const now = new Date();
  const emitido = `${String(now.getDate()).padStart(2, "0")}/${String(now.getMonth() + 1).padStart(2, "0")}/${now.getFullYear()}`;

  let y = margin;

  doc.save();
  doc.roundedRect(margin, y, innerW, 56, 10).fill(HEADER_BLUE);
  doc.fillColor("#ffffff").font("Helvetica-Bold").fontSize(17).text("Controle Total App", margin + 14, y + 12, {
    width: 280,
  });
  doc.font("Helvetica").fontSize(10).text("Extrato Super Premium", margin + 14, y + 34, { width: 280 });
  doc.font("Helvetica-Bold").fontSize(9).fillColor("#ffffff");
  const perLabel = periodo ? `Período: ${_clampStr(periodo, 70)}` : "Período";
  doc.text(perLabel, margin + innerW - 200 - 14, y + 18, { width: 200, align: "right" });
  doc.restore();
  y += 64;

  doc.fillColor(MUTED).font("Helvetica").fontSize(9);
  doc.text(`Utilizador: ${nomeUsuario ? _clampStr(nomeUsuario, 72) : "-"}`, margin, y);
  y += 12;
  doc.text(`Conta: ${conta ? _clampStr(conta, 72) : "Todas as contas"}`, margin, y);
  y += 16;

  const boxH = 44;
  const gap = 5;
  const boxW = (innerW - gap * 3) / 4;
  const mini = [
    { t: "RECEITAS", v: _fmtMoneyBr(totalReceitas), c: "#166534" },
    { t: "DESPESAS", v: _fmtMoneyBr(totalDespesas), c: "#991b1b" },
    { t: "SALDO PERÍODO", v: _fmtMoneyBr(saldoPeriodo), c: saldoPeriodo >= 0 ? HEADER_BLUE : "#991b1b" },
    { t: "SALDO FINAL", v: _fmtMoneyBr(saldoFinal), c: saldoFinal >= 0 ? HEADER_BLUE : "#991b1b" },
  ];
  for (let i = 0; i < 4; i++) {
    const x = margin + i * (boxW + gap);
    doc.save();
    doc.roundedRect(x, y, boxW, boxH, 8).fill(BOX_BG);
    doc.lineWidth(0.45).strokeColor(BOX_BORDER).roundedRect(x, y, boxW, boxH, 8).stroke();
    doc.fillColor(MUTED).font("Helvetica-Bold").fontSize(6.5).text(mini[i].t, x + 8, y + 8, { width: boxW - 16 });
    doc.fillColor(mini[i].c).font("Helvetica-Bold").fontSize(8.5).text(mini[i].v, x + 8, y + 22, { width: boxW - 16 });
    doc.restore();
  }
  y += boxH + 16;

  doc.fillColor(HEADER_BLUE).font("Helvetica-Bold").fontSize(11).text("Movimentos (extrato)", margin, y);
  y += 16;

  const headH = 18;
  const rowPad = 3;
  const pageBottom = 762;

  const drawHead = (yy) => {
    doc.save();
    doc.rect(margin, yy, innerW, headH).fill(TABLE_HEAD_BLUE);
    doc.fillColor("#ffffff").font("Helvetica-Bold").fontSize(8);
    doc.text("Data", margin + 6, yy + 5, { width: 50 });
    doc.text("Descrição", margin + 58, yy + 5, { width: 248 });
    doc.text("Entrada", margin + 312, yy + 5, { width: 76, align: "right" });
    doc.text("Saída", margin + 392, yy + 5, { width: 68, align: "right" });
    doc.text("Saldo", margin + 468, yy + 5, { width: innerW - 468 - 8, align: "right" });
    doc.restore();
    return yy + headH + 2;
  };

  y = drawHead(y);

  doc.fillColor(TEXT).font("Helvetica").fontSize(8);
  for (const ln of linhas) {
    const rowH = 16;
    if (y + rowH > pageBottom) {
      doc.addPage();
      y = margin + 8;
      y = drawHead(y);
      doc.fillColor(TEXT).font("Helvetica").fontSize(8);
    }
    const yy = y;
    doc.text(ln.data || "", margin + 6, yy + rowPad, { width: 50 });
    doc.text(ln.desc || "", margin + 58, yy + rowPad, { width: 248, lineBreak: false });
    doc.text(ln.ent || "", margin + 312, yy + rowPad, { width: 76, align: "right" });
    doc.text(ln.sai || "", margin + 392, yy + rowPad, { width: 68, align: "right" });
    doc.text(ln.saldo || "", margin + 468, yy + rowPad, { width: innerW - 468 - 8, align: "right" });
    y += rowH;
  }

  y = Math.min(y + 14, pageBottom);
  doc.fillColor(MUTED).font("Helvetica").fontSize(7.5).text(`Emitido em ${emitido}  |  Controle Total App`, margin, y, {
    width: innerW,
    align: "right",
  });
}

/**
 * @param {typeof import('pdfkit')} PDFDocumentCtor
 * @param {object} opts — mesmo shape que drawFinanceSuperExtrato
 * @returns {Promise<Buffer>}
 */
function buildFinanceSuperExtratoPdfBuffer(PDFDocumentCtor, opts) {
  const doc = new PDFDocumentCtor({
    margin: 22,
    size: "A4",
    bufferPages: true,
    info: { Title: "Extrato Super Premium", Author: "Controle Total App", Creator: "Controle Total App" },
  });
  const chunks = [];
  doc.on("data", (c) => chunks.push(c));
  const done = new Promise((resolve, reject) => {
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);
  });
  drawFinanceSuperExtrato(doc, opts);
  doc.end();
  return done;
}

module.exports = {
  _clampStr,
  _fmtMoneyBr,
  buildExtratoLinhas,
  drawFinanceSuperExtrato,
  buildFinanceSuperExtratoPdfBuffer,
};
