"""Gera o SQL que chama obra.importacao_criar() com as linhas normalizadas (para carga via SQL)."""
import hashlib, json, sys
linhas = open(sys.argv[1], encoding="utf-8").read()
sha = hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest()
nome = sys.argv[3]
sub = sys.argv[4]
print(f"""select set_config('request.jwt.claims', '{{"sub":"{sub}","role":"authenticated","email":"raf.fcp@gmail.com"}}', true);
select obra.importacao_criar((select id from obra.obra where nome = 'Casa Villagio Tunis' and excluido_em is null),
  '{nome}', '{sha}', $json${linhas}$json$::jsonb) as importacao_id;""")
