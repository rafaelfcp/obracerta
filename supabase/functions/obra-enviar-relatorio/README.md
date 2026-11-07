# obra-enviar-relatorio

Edge Function que gera os relatórios do ObraCerta e envia por e-mail.

- `POST { acao: "preview", tipo, obra_id, mensagem? }` → `{ assunto, html, dados }` (o HTML é exatamente o do e-mail).
- `POST { acao: "enviar", tipo, obra_id, destinatarios[], assunto?, mensagem? }` → envia e grava em `obra.relatorio_envio`.

Segurança: `verify_jwt = true`; usa o token do próprio usuário com a anon key (sem service_role), então a RLS e
`obra.exigir_membro` valem como no app. Só acessa o schema `obra`. Limites: 10 destinatários por envio e
10 envios por hora por usuário.

## E-mail

Provedor escolhido pelos secrets da função (Dashboard → Edge Functions → Secrets):

| Secret | Uso |
|---|---|
| `GMAIL_USER` | endereço Gmail remetente |
| `GMAIL_APP_PASSWORD` | senha de app do Google (myaccount.google.com/apppasswords) |
| `RESEND_API_KEY`, `RELATORIO_REMETENTE` | alternativa, usada só se não houver os secrets do Gmail |

O Gmail é acessado em `smtp.gmail.com:465` (TLS direto): as Edge Functions bloqueiam as portas 25 e 587.
O "De:" aparece como "<nome de quem enviou> via ObraCerta" e o Reply-To é o e-mail de quem enviou.

## Deploy

```bash
supabase functions deploy obra-enviar-relatorio --project-ref lfagemsbgtzlqjjagrmn
```

## Novo relatório

1. Banco: `obra.relatorio_<tipo>(obra)` e incluir o tipo no CHECK de `obra.relatorio_envio.tipo`.
2. Aqui: aceitar o `tipo` e criar o renderizador (ver `render.ts`).
3. App: marcar `disponivel: true` em `app/src/lib/relatorios.ts`.
