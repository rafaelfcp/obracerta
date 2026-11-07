// Envio de e-mail do ObraCerta.
// Provedor escolhido pelos secrets da Edge Function:
//   1) Gmail SMTP  — GMAIL_USER + GMAIL_APP_PASSWORD (senha de app do Google, 16 caracteres)
//                    smtp.gmail.com:465 (TLS direto). As portas 25/587 são bloqueadas nas Edge Functions.
//   2) Resend      — RESEND_API_KEY (+ RELATORIO_REMETENTE opcional)
//   Sem nenhum → "nao_configurado".
import nodemailer from "npm:nodemailer@6.9.16";

export type Mensagem = {
  para: string[];
  assunto: string;
  html: string;
  texto: string;
  /** e-mail de quem disparou no app (vira Reply-To) */
  responderPara?: string | null;
  /** nome de quem disparou (aparece no "De": "Fulano via ObraCerta") */
  nomeExibicao?: string | null;
  anexo?: { nome: string; conteudo: string; tipo: string };
};

export type Resultado =
  | { ok: true; provedor: "gmail" | "resend"; id: string | null }
  | { ok: false; provedor: "gmail" | "resend" | "nenhum"; erro: string; naoConfigurado?: boolean };

type Env = (k: string) => string | undefined;

export function provedorConfigurado(env: Env): "gmail" | "resend" | "nenhum" {
  if (env("GMAIL_USER") && env("GMAIL_APP_PASSWORD")) return "gmail";
  if (env("RESEND_API_KEY")) return "resend";
  return "nenhum";
}

// Remove CR/LF e aspas de nomes que vão para cabeçalho (evita header injection)
const limparNome = (s: string) => s.replace(/[\r\n"<>]/g, " ").replace(/\s+/g, " ").trim().slice(0, 60);

export function montarGmail(env: Env, m: Mensagem) {
  const usuario = env("GMAIL_USER")!.trim();
  const nome = limparNome(m.nomeExibicao ? `${m.nomeExibicao} via ObraCerta` : "ObraCerta");
  const replyTo = m.responderPara && m.responderPara.toLowerCase() !== usuario.toLowerCase()
    ? m.responderPara : undefined;
  return {
    transporte: {
      host: "smtp.gmail.com",
      port: 465,
      secure: true, // TLS implícito (465). Não usar 587/STARTTLS: bloqueado no runtime.
      auth: { user: usuario, pass: env("GMAIL_APP_PASSWORD")!.replace(/\s+/g, "") }, // Google mostra a senha com espaços
      connectionTimeout: 15_000,
      greetingTimeout: 10_000,
      socketTimeout: 20_000,
    },
    mensagem: {
      from: { name: nome, address: usuario },
      to: m.para,
      ...(replyTo ? { replyTo } : {}),
      subject: m.assunto,
      text: m.texto,
      html: m.html,
      attachments: m.anexo
        ? [{ filename: m.anexo.nome, content: m.anexo.conteudo, contentType: m.anexo.tipo }]
        : [],
    },
  };
}

async function viaGmail(env: Env, m: Mensagem): Promise<Resultado> {
  const { transporte, mensagem } = montarGmail(env, m);
  try {
    const t = nodemailer.createTransport(transporte);
    const info = await t.sendMail(mensagem);
    t.close();
    return { ok: true, provedor: "gmail", id: info.messageId ?? null };
  } catch (e) {
    const err = e as { code?: string; responseCode?: number; message?: string };
    // 535 = usuário/senha rejeitados (senha normal em vez de senha de app, ou senha revogada)
    const dica = err.responseCode === 535
      ? " — o Google recusou o login. Use uma senha de app (não a senha da conta) e confira GMAIL_USER."
      : "";
    return { ok: false, provedor: "gmail", erro: `${err.responseCode ?? err.code ?? "smtp"}: ${err.message ?? "falha"}${dica}` };
  }
}

async function viaResend(env: Env, m: Mensagem): Promise<Resultado> {
  const bytes = new TextEncoder().encode(m.anexo?.conteudo ?? "");
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  try {
    const resp = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${env("RESEND_API_KEY")}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: env("RELATORIO_REMETENTE") ?? "ObraCerta <onboarding@resend.dev>",
        to: m.para,
        subject: m.assunto,
        html: m.html,
        text: m.texto,
        ...(m.responderPara ? { reply_to: m.responderPara } : {}),
        ...(m.anexo ? { attachments: [{ filename: m.anexo.nome, content: btoa(bin) }] } : {}),
      }),
    });
    const out = await resp.json().catch(() => ({}));
    if (!resp.ok) return { ok: false, provedor: "resend", erro: `${resp.status}: ${out?.message ?? out?.name ?? "falha no provedor"}` };
    return { ok: true, provedor: "resend", id: out?.id ?? null };
  } catch (e) {
    return { ok: false, provedor: "resend", erro: `rede: ${(e as Error).message}` };
  }
}

export async function enviarEmail(env: Env, m: Mensagem): Promise<Resultado> {
  switch (provedorConfigurado(env)) {
    case "gmail": return viaGmail(env, m);
    case "resend": return viaResend(env, m);
    default:
      return { ok: false, provedor: "nenhum", naoConfigurado: true,
        erro: "Envio por e-mail não configurado: cadastre GMAIL_USER e GMAIL_APP_PASSWORD nos secrets da Edge Function." };
  }
}
