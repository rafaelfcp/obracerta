# ObraCerta — app (React PWA)

App mobile do controle da obra. Lê e grava somente no schema `obra` do Supabase (isolado do DashBoard-Financeiro).

## Rodar local
```bash
cd app
npm install
npm run dev        # http://localhost:5173
```

## Telas (v0.1)
- Login por e-mail e senha, "primeiro acesso" (criar conta) e "esqueci a senha". No primeiro login, `obra.aceitar_convites()` vira o convite em membro.
- Painel (`v_obra_painel` + 5 maiores etapas), Etapas e detalhe (`v_etapa_painel` + itens), Orçamento com filtros e busca (`v_item_resumo`), Alertas (`v_alerta`), Conta.

## Deploy
Workflow `.github/workflows/deploy-app.yml`: cada push na `main` que mexe em `app/` gera o build e publica no GitHub Pages.
As rotas usam `#` (HashRouter), então funciona em `https://<usuario>.github.io/<repo>/` sem configuração extra.
