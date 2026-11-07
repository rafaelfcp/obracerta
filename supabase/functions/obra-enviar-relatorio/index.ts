// Edge Function: obra-enviar-relatorio
// POST { acao: "preview" | "enviar", tipo: "status_etapas", obra_id, destinatarios?, assunto?, mensagem? }
//
// Segurança / isolamento:
//  - verify_jwt = true (gateway valida o token) e o cliente Supabase usa o MESMO token do usuário,
//    então RLS + obra.exigir_membro valem igual ao app. Sem service_role.
//  - Só fala com o schema "obra". Nunca toca public.
//  - Limites: até 10 destinatários por envio, 10 envios/hora por usuário (contados no log).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { renderStatusEtapas, type RelatorioStatusEtapas } from "./render.ts";
import { enviarEmail, provedorConfigurado } from "./email.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const EMAIL_RE = /^[A-Z0-9._%+\-]+@[A-Z0-9\-]+(\.[A-Z0-9\-]+)*\.[A-Z]{2,}$/i;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_DEST = 10;
const MAX_ENVIOS_HORA = 10;

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const erro = (status: number, codigo: string, mensagem: string) => json(status, { erro: codigo, mensagem });

function claimsDoToken(auth: string): Record<string, unknown> {
  try {
    const p = auth.replace(/^Bearer\s+/i, "").split(".")[1];
    const bin = atob(p.replace(/-/g, "+").replace(/_/g, "/"));
    // atob devolve bytes; decodifica UTF-8 para nomes com acento não virarem mojibake no "De:"
    return JSON.parse(new TextDecoder().decode(Uint8Array.from(bin, (c) => c.charCodeAt(0))));
  } catch {
    return {};
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return erro(405, "OC_METODO", "Use POST.");

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return erro(401, "OC_SEM_TOKEN", "Faça login para gerar relatórios.");

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return erro(400, "OC_JSON", "Corpo inválido.");
  }

  const acao = body.acao === "enviar" ? "enviar" : "preview";
  const tipo = String(body.tipo ?? "status_etapas");
  const obraId = String(body.obra_id ?? "");
  if (tipo !== "status_etapas") return erro(400, "OC_TIPO", `Relatório "${tipo}" não existe.`);
  if (!UUID_RE.test(obraId)) return erro(400, "OC_OBRA", "obra_id inválido.");

  const mensagem = body.mensagem == null ? null : String(body.mensagem).slice(0, 2000);
  const claims = claimsDoToken(auth);
  const meta = (claims.user_metadata ?? {}) as Record<string, unknown>;
  const emailUsuario = typeof claims.email === "string" ? claims.email : null;
  const nomeUsuario = (typeof meta.full_name === "string" && meta.full_name) ||
    (typeof meta.name === "string" && meta.name) || emailUsuario;

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const sb = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
    db: { schema: "obra" },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1) Dados (RLS do usuário)
  const { data: dados, error: errDados } = await sb.rpc("relatorio_status_etapas", { p_obra: obraId });
  if (errDados) {
    const semPermissao = errDados.message?.includes("OC_SEM_PERMISSAO");
    return erro(semPermissao ? 403 : 400, semPermissao ? "OC_SEM_PERMISSAO" : "OC_DADOS", errDados.message);
  }
  const rel = dados as RelatorioStatusEtapas;
  const r = renderStatusEtapas(rel, { mensagem, enviadoPor: nomeUsuario });

  if (acao === "preview") {
    return json(200, { assunto: r.assuntoPadrao, html: r.html, dados: rel });
  }

  // 2) Validação dos destinatários
  const brutos = Array.isArray(body.destinatarios) ? body.destinatarios : String(body.destinatarios ?? "").split(/[,;\s]+/);
  const destinatarios = [...new Set(brutos.map((d) => String(d).trim().toLowerCase()).filter(Boolean))];
  if (destinatarios.length === 0) return erro(400, "OC_DEST_VAZIO", "Informe ao menos um destinatário.");
  if (destinatarios.length > MAX_DEST) return erro(400, "OC_DEST_MAX", `Máximo de ${MAX_DEST} destinatários por envio.`);
  const invalidos = destinatarios.filter((d) => d.length > 254 || !EMAIL_RE.test(d));
  if (invalidos.length) return erro(400, "OC_DEST_INVALIDO", `E-mail(s) inválido(s): ${invalidos.join(", ")}`);

  const assunto = (String(body.assunto ?? "").trim() || r.assuntoPadrao).slice(0, 200);

  // 3) Rate limit
  const { data: qtd, error: errQtd } = await sb.rpc("relatorio_envios_ultima_hora");
  if (errQtd) return erro(500, "OC_RATE", errQtd.message);
  if ((qtd as number) >= MAX_ENVIOS_HORA) {
    return erro(429, "OC_LIMITE", `Limite de ${MAX_ENVIOS_HORA} envios por hora atingido. Tente mais tarde.`);
  }

  // 4) Envio (Gmail SMTP se configurado; senão Resend)
  const env = (k: string) => Deno.env.get(k);
  if (provedorConfigurado(env) === "nenhum") {
    // Diagnóstico sem expor valores: só diz quais nomes existem e se estão vazios,
    // e lista nomes parecidos (ex.: "gmail_user", "GMAIL_USER ") para pegar erro de digitação.
    const st = (k: string) => (env(k) === undefined ? "ausente" : env(k)!.trim() ? "ok" : "vazio");
    const parecidos = Object.keys(Deno.env.toObject())
      .filter((k) => /gmail|app_?pass|resend/i.test(k) && !["GMAIL_USER", "GMAIL_APP_PASSWORD", "RESEND_API_KEY"].includes(k));
    return erro(503, "OC_EMAIL_NAO_CONFIGURADO",
      `Envio por e-mail não configurado. GMAIL_USER: ${st("GMAIL_USER")}; GMAIL_APP_PASSWORD: ${st("GMAIL_APP_PASSWORD")}` +
      (parecidos.length ? `; nomes parecidos encontrados: ${parecidos.map((k) => JSON.stringify(k)).join(", ")}` : "") +
      ". Cadastre os dois nos secrets da Edge Function do projeto Controle_Financeiro.");
  }
  const hoje = rel.gerado_em.slice(0, 10);
  const res = await enviarEmail(env, {
    para: destinatarios,
    assunto,
    html: r.html,
    texto: r.text,
    responderPara: emailUsuario,
    nomeExibicao: nomeUsuario,
    anexo: { nome: `status-etapas-${hoje}.csv`, conteudo: r.csv, tipo: "text/csv; charset=utf-8" },
  });
  const status: "enviado" | "erro" = res.ok ? "enviado" : "erro";
  const provedorId = res.ok ? res.id : null;
  const falha = res.ok ? null : res.erro;

  // 5) Log (sempre, inclusive falhas)
  const { data: log, error: errLog } = await sb.from("relatorio_envio").insert({
    obra_id: obraId,
    tipo,
    destinatarios,
    assunto,
    mensagem,
    parametros: { provedor: res.provedor },
    resumo: { obra: rel.obra, totais: rel.totais, gerado_em: rel.gerado_em },
    status,
    provedor_id: provedorId,
    erro: falha,
  }).select("id, criado_em").single();

  if (status === "erro") return erro(502, "OC_EMAIL_FALHOU", falha ?? "Falha no envio.");
  return json(200, {
    ok: true, envio_id: log?.id ?? null, provedor_id: provedorId, destinatarios, assunto,
    aviso_log: errLog ? `E-mail enviado, mas o log falhou: ${errLog.message}` : undefined,
  });
});
