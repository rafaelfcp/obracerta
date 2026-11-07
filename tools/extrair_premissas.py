"""Extrai as premissas da aba Quantitativos (áreas e parâmetros) para JSON."""
import json, re, sys, unicodedata
import openpyxl

PDF = {5, 6, 7, 8, 9, 10, 20, 22}   # linhas alteradas para a planta PDF em 06/11/2026
LAV2 = {24}                         # linha alterada pelo 2º lavabo

def slug(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "_", s).strip("_")[:60]

ws = openpyxl.load_workbook(sys.argv[1], data_only=True)["Quantitativos"]
out = []
for r in range(5, 35):
    rot, val, uni, obs = (ws.cell(r, c).value for c in (2, 3, 4, 6))
    if rot is None or not isinstance(val, (int, float)):
        continue
    fonte = "Planta PDF (06/11/2026)" if r in PDF else ("Planilha v2 + 2º lavabo" if r in LAV2 else "Planilha v2")
    out.append({"chave": slug(rot), "valor": round(float(val), 4), "unidade": uni, "fonte": fonte, "observacao": rot})
for r, chave in ((46, "perda_material"), (47, "bdi_empreiteiro")):
    out.append({"chave": chave, "valor": float(ws.cell(r, 3).value), "unidade": "%", "fonte": "Planilha v2",
                "observacao": ws.cell(r, 2).value})
json.dump(out, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(len(out), "premissas")
