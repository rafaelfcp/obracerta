// Renderizador do relatório "Resumo de Status das Etapas".
// Função pura (sem I/O): recebe o JSON de obra.relatorio_status_etapas e devolve
// HTML de e-mail (tabelas + estilos inline, funciona em Gmail/Outlook), texto puro e CSV.

export type Etapa = {
  ordem: number; nome: string; status: string; situacao: string;
  responsavel: string | null;
  inicio_previsto: string | null; fim_previsto: string | null;
  inicio_real: string | null; fim_real: string | null;
  pct_fisico: number; pct_financeiro: number | null;
  orcado: number; contratado: number; pago: number; a_pagar: number;
  desvio: number | null; desvio_pct: number | null;
  atrasada: boolean; semaforo: string;
};

export type RelatorioStatusEtapas = {
  tipo: "status_etapas";
  gerado_em: string;
  obra: {
    id: string; nome: string; status_geral: string;
    inicio_previsto: string | null; conclusao_prevista: string | null;
    orcado_total: number; orcado_obra: number; pago: number; contratado: number;
    pct_fisico: number; pct_financeiro_pago: number; etapas_atrasadas: number; semaforo: string;
  };
  totais: {
    etapas: number; planejada: number; em_andamento: number; pausada: number;
    concluida: number; cancelada: number; atrasadas: number;
    sem_orcamento: number; sem_datas: number;
    orcado: number; contratado: number; pago: number;
  };
  etapas: Etapa[];
};

export type Render = { html: string; text: string; csv: string; assuntoPadrao: string };

const STATUS: Record<string, { rotulo: string; cor: string; fundo: string }> = {
  planejada:    { rotulo: "Planejada",    cor: "#475569", fundo: "#f1f5f9" },
  em_andamento: { rotulo: "Em andamento", cor: "#1d4ed8", fundo: "#dbeafe" },
  pausada:      { rotulo: "Pausada",      cor: "#a16207", fundo: "#fef3c7" },
  concluida:    { rotulo: "Concluída",    cor: "#15803d", fundo: "#dcfce7" },
  cancelada:    { rotulo: "Cancelada",    cor: "#6b7280", fundo: "#e5e7eb" },
};

const SITUACAO: Record<string, string> = {
  a_fazer: "A fazer", em_andamento: "Em andamento",
  aguardando_aprovacao: "Aguardando aprovação", aguardando_material: "Aguardando material",
  aguardando_pagamento: "Aguardando pagamento", pausada: "Pausada", concluida: "Concluída",
};

const SEMAFORO: Record<string, { rotulo: string; cor: string }> = {
  verde:         { rotulo: "No orçamento",  cor: "#16a34a" },
  amarelo:       { rotulo: "Atenção",       cor: "#d97706" },
  vermelho:      { rotulo: "Estourado",     cor: "#dc2626" },
  sem_orcamento: { rotulo: "Sem orçamento", cor: "#94a3b8" },
};

const brl = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
const num2 = new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export const moeda = (v: number | null | undefined) => brl.format(Number(v ?? 0));
export const pct = (v: number | null | undefined, casas = 1) =>
  v == null ? "—" : `${(Number(v) * 100).toFixed(casas).replace(".", ",")}%`;
export const data = (iso: string | null | undefined) => {
  if (!iso) return "—";
  const [a, m, d] = iso.slice(0, 10).split("-");
  return `${d}/${m}/${a}`;
};
const dataHora = (iso: string) =>
  new Intl.DateTimeFormat("pt-BR", {
    timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", year: "numeric",
    hour: "2-digit", minute: "2-digit",
  }).format(new Date(iso));

export const esc = (s: unknown) =>
  String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");

function prazo(e: Etapa): string {
  if (e.fim_real) return `Concluída em ${data(e.fim_real)}`;
  if (!e.inicio_previsto && !e.fim_previsto) return "Sem datas previstas";
  const base = `${data(e.inicio_previsto)} → ${data(e.fim_previsto)}`;
  return e.atrasada ? `${base} · ATRASADA` : base;
}

function barra(p: number, cor: string): string {
  const w = Math.max(0, Math.min(100, Math.round(p * 100)));
  // Barra em tabela: renderiza igual em Outlook (sem div/flex)
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;">
<tr>${w > 0 ? `<td width="${w}%" style="background:${cor};height:6px;font-size:0;line-height:0;">&nbsp;</td>` : ""}
<td style="background:#e2e8f0;height:6px;font-size:0;line-height:0;">&nbsp;</td></tr></table>`;
}

function kpi(rotulo: string, valor: string, detalhe = ""): string {
  return `<td valign="top" style="padding:10px 12px;border:1px solid #e2e8f0;border-radius:8px;background:#ffffff;">
<div style="font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:.04em;">${esc(rotulo)}</div>
<div style="font-size:18px;font-weight:700;color:#0f172a;margin-top:2px;">${esc(valor)}</div>
${detalhe ? `<div style="font-size:12px;color:#64748b;margin-top:2px;">${esc(detalhe)}</div>` : ""}
</td>`;
}

export function renderStatusEtapas(
  r: RelatorioStatusEtapas,
  opts: { mensagem?: string | null; enviadoPor?: string | null } = {},
): Render {
  const { obra, totais: t, etapas } = r;
  const gerado = dataHora(r.gerado_em);
  const assuntoPadrao = `ObraCerta · ${obra.nome} · Status das etapas (${data(r.gerado_em.slice(0, 10))})`;

  // ---------- alertas ----------
  const alertas: string[] = [];
  if (t.atrasadas > 0) alertas.push(`${t.atrasadas} etapa(s) atrasada(s)`);
  const estouradas = etapas.filter((e) => e.semaforo === "vermelho").length;
  const atencao = etapas.filter((e) => e.semaforo === "amarelo").length;
  if (estouradas > 0) alertas.push(`${estouradas} etapa(s) acima do orçamento`);
  if (atencao > 0) alertas.push(`${atencao} etapa(s) perto do limite do orçamento`);
  if (t.sem_orcamento > 0) alertas.push(`${t.sem_orcamento} etapa(s) sem orçamento`);
  if (t.sem_datas > 0) alertas.push(`${t.sem_datas} de ${t.etapas} etapa(s) sem datas previstas`);

  // ---------- linhas das etapas ----------
  const linhas = etapas.map((e) => {
    const st = STATUS[e.status] ?? STATUS.planejada;
    const sem = SEMAFORO[e.semaforo] ?? SEMAFORO.verde;
    const situacao = SITUACAO[e.situacao] && e.situacao !== e.status ? ` · ${SITUACAO[e.situacao]}` : "";
    const corBarra = e.status === "concluida" ? "#16a34a" : "#2563eb";
    return `<tr><td style="padding:12px 0;border-bottom:1px solid #e2e8f0;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
<td valign="top" style="font-size:14px;color:#0f172a;font-weight:600;">
  <span style="color:#94a3b8;font-weight:400;">${e.ordem}.</span> ${esc(e.nome)}
</td>
<td valign="top" align="right" style="white-space:nowrap;">
  <span style="display:inline-block;font-size:11px;font-weight:600;color:${st.cor};background:${st.fundo};padding:2px 8px;border-radius:999px;">${st.rotulo}</span>
</td></tr>
<tr><td colspan="2" style="padding-top:6px;">${barra(e.pct_fisico, corBarra)}</td></tr>
<tr><td colspan="2" style="padding-top:6px;font-size:12px;color:#475569;line-height:1.5;">
  Físico <b>${pct(e.pct_fisico, 0)}</b> · Orçado <b>${moeda(e.orcado)}</b> · Pago <b>${moeda(e.pago)}</b>${
      e.contratado > 0 ? ` · Contratado ${moeda(e.contratado)}` : ""}<br>
  <span style="color:${sem.cor};">●</span> ${sem.rotulo}${
      e.desvio_pct ? ` (${e.desvio! > 0 ? "+" : ""}${pct(e.desvio_pct)})` : ""} · ${esc(prazo(e))}${esc(situacao)}${
      e.responsavel ? ` · Resp.: ${esc(e.responsavel)}` : ""}
</td></tr></table></td></tr>`;
  }).join("\n");

  const msgHtml = opts.mensagem?.trim()
    ? `<tr><td style="padding:0 24px 16px;"><div style="font-size:14px;color:#0f172a;line-height:1.55;background:#f8fafc;border-left:3px solid #2563eb;padding:10px 14px;">${
      esc(opts.mensagem.trim()).replace(/\n/g, "<br>")}</div></td></tr>`
    : "";

  const alertasHtml = alertas.length
    ? `<tr><td style="padding:0 24px 16px;"><div style="font-size:13px;color:#92400e;background:#fffbeb;border:1px solid #fde68a;border-radius:8px;padding:10px 14px;line-height:1.6;">
<b>Pontos de atenção</b><br>${alertas.map((a) => `• ${esc(a)}`).join("<br>")}</div></td></tr>`
    : "";

  const html = `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(assuntoPadrao)}</title></head>
<body style="margin:0;padding:0;background:#f1f5f9;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f1f5f9;"><tr><td align="center" style="padding:24px 12px;">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:12px;overflow:hidden;">
<tr><td style="background:#0f172a;padding:20px 24px;">
  <div style="font-size:12px;color:#94a3b8;letter-spacing:.06em;text-transform:uppercase;">ObraCerta · Relatório</div>
  <div style="font-size:20px;font-weight:700;color:#ffffff;margin-top:4px;">Resumo de status das etapas</div>
  <div style="font-size:13px;color:#cbd5e1;margin-top:4px;">${esc(obra.nome)} · gerado em ${gerado}</div>
</td></tr>
<tr><td style="padding:20px 24px 8px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="6" style="border-collapse:separate;"><tr>
${kpi("Avanço físico", pct(obra.pct_fisico), `${t.concluida} de ${t.etapas} etapas concluídas`)}
${kpi("Orçado da obra", moeda(obra.orcado_obra), `Total c/ lote: ${moeda(obra.orcado_total)}`)}
</tr><tr>
${kpi("Pago (total)", moeda(obra.pago), `${pct(obra.pct_financeiro_pago, 2)} do orçado total`)}
${kpi("Etapas", `${t.em_andamento} em andamento`, `${t.planejada} planejadas · ${t.pausada} pausadas · ${t.atrasadas} atrasadas`)}
</tr></table></td></tr>
${msgHtml}
${alertasHtml}
<tr><td style="padding:0 24px;">
<div style="font-size:15px;font-weight:700;color:#0f172a;padding:8px 0 4px;">Etapas</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${linhas}</table>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
<td style="padding:12px 0;font-size:13px;color:#0f172a;"><b>Soma das etapas</b> · Orçado ${moeda(t.orcado)} · Contratado ${moeda(t.contratado)} · Pago ${moeda(t.pago)}</td>
</tr></table>
</td></tr>
<tr><td style="padding:16px 24px 24px;font-size:11px;color:#94a3b8;line-height:1.5;border-top:1px solid #e2e8f0;">
Valores do orçado da etapa incluem o rateio de custos indiretos. "Pago (total)" inclui o lote; a soma das etapas considera só a obra.
Planilha em anexo (CSV) com os mesmos dados.${opts.enviadoPor ? `<br>Enviado por ${esc(opts.enviadoPor)} pelo ObraCerta.` : ""}
</td></tr>
</table></td></tr></table></body></html>`;

  // ---------- texto puro (fallback de clientes sem HTML) ----------
  const text = [
    `ObraCerta — Resumo de status das etapas`,
    `${obra.nome} · gerado em ${gerado}`,
    ``,
    opts.mensagem?.trim() ? `${opts.mensagem.trim()}\n` : null,
    `Avanço físico: ${pct(obra.pct_fisico)} | Orçado obra: ${moeda(obra.orcado_obra)} | Pago (total): ${moeda(obra.pago)} (${pct(obra.pct_financeiro_pago, 2)})`,
    `Etapas: ${t.etapas} (${t.em_andamento} em andamento, ${t.concluida} concluídas, ${t.atrasadas} atrasadas)`,
    alertas.length ? `\nPontos de atenção:\n${alertas.map((a) => `- ${a}`).join("\n")}` : null,
    ``,
    ...etapas.map((e) =>
      `${String(e.ordem).padStart(2, " ")}. ${e.nome} — ${STATUS[e.status]?.rotulo ?? e.status} | físico ${pct(e.pct_fisico, 0)} | orçado ${moeda(e.orcado)} | pago ${moeda(e.pago)} | ${prazo(e)}`
    ),
  ].filter((l) => l !== null).join("\n");

  // ---------- CSV (; e vírgula decimal = abre direto no Excel pt-BR) ----------
  const c = (v: unknown) => {
    let s = String(v ?? "");
    if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`; // evita injeção de fórmula no Excel
    return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const n = (v: number | null) => (v == null ? "" : num2.format(v).replace(/\./g, ""));
  const cab = ["Ordem", "Etapa", "Status", "Situação", "Responsável", "Início previsto", "Fim previsto",
    "Início real", "Fim real", "% físico", "% financeiro", "Orçado", "Contratado", "Pago", "A pagar",
    "Desvio", "Desvio %", "Atrasada", "Semáforo"];
  const csv = "\uFEFF" + [cab.join(";"), ...etapas.map((e) => [
    e.ordem, c(e.nome), STATUS[e.status]?.rotulo ?? e.status, SITUACAO[e.situacao] ?? e.situacao,
    c(e.responsavel), data(e.inicio_previsto).replace("—", ""), data(e.fim_previsto).replace("—", ""),
    data(e.inicio_real).replace("—", ""), data(e.fim_real).replace("—", ""),
    n(e.pct_fisico * 100), n(e.pct_financeiro == null ? null : e.pct_financeiro * 100),
    n(e.orcado), n(e.contratado), n(e.pago), n(e.a_pagar), n(e.desvio),
    n(e.desvio_pct == null ? null : e.desvio_pct * 100), e.atrasada ? "Sim" : "Não",
    SEMAFORO[e.semaforo]?.rotulo ?? e.semaforo,
  ].join(";"))].join("\r\n");

  return { html, text, csv, assuntoPadrao };
}
