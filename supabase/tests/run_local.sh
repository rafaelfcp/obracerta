#!/usr/bin/env bash
# Recria o banco local, aplica migrations + seed e roda a importação da planilha.
set -euo pipefail
cd "$(dirname "$0")/../.."
P="psql -h /var/tmp/ocpg -p 5499 -U postgres -v ON_ERROR_STOP=1 -q"
$P -c "drop database if exists oc" -c "create database oc"
$P -d oc -f supabase/tests/00_supabase_stub.sql
for f in supabase/migrations/*.sql; do $P -d oc -f "$f"; done
$P -d oc -f supabase/seed/casa_villagio.sql 2>/dev/null
python3 -I tools/sql_importacao.py data/itens_v3.json data/orcamento_v3_planta_pdf.xlsx \
  orcamento_v3_planta_pdf.xlsx 05c1d5f2-b450-4828-87f4-71a9cb638580 > /tmp/imp.sql
$P -d oc -1 -f /tmp/imp.sql -At >/dev/null
echo "ok: banco local recriado e planilha em revisão"
