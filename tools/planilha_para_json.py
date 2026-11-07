"""Normaliza a aba Itens da planilha de orçamento para o formato de obra.importacao_criar().

Uso: python3 -I planilha_para_json.py <planilha.xlsx> <saida.json>

Regras (iguais às do importador do app):
  - preços K/L/M -> precos {economico, medio, alto} (só os preenchidos)
  - sem nenhum preço -> valor_fixo = coluna S (cenário "Meu")
  - quantidade arredondada a 3 casas, preços a 4
  - base_contingencia = classe "Obra principal" ou "Extras da obra" (regra da planilha)
  - linha original preservada em "bruto" (coluna -> valor)
"""
import datetime as dt
import json
import sys

import openpyxl

CENARIO = {"Econômico": "economico", "Médio": "medio", "Alto": "alto"}
COLS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


def num(v, casas=None):
    if v is None or v == "":
        return None
    if isinstance(v, (int, float)):
        return round(float(v), casas) if casas is not None else float(v)
    try:
        return round(float(str(v).replace(",", ".")), casas) if casas is not None else float(str(v).replace(",", "."))
    except ValueError:
        return None


def txt(v):
    if v is None:
        return None
    s = " ".join(str(v).split())
    return s or None


def main(origem, destino):
    ws = openpyxl.load_workbook(origem, data_only=True)["Itens"]
    linhas = []
    for r in range(5, ws.max_row + 1):
        c = {COLS[i]: ws.cell(r, i + 1).value for i in range(26)}
        if not c["B"] or not c["D"]:
            continue  # totais e linhas vazias ficam de fora
        precos = {k: num(c[col], 4) for k, col in (("economico", "K"), ("medio", "L"), ("alto", "M"))
                  if num(c[col]) is not None}
        pago = None
        if txt(c["U"]):
            data = c["W"]
            pago = {
                "status": txt(c["U"]).lower(),
                "valor": num(c["V"], 2),
                "data": data.date().isoformat() if isinstance(data, dt.datetime) else txt(data),
                "forma": txt(c["X"]),
            }
        bruto = {k: (v.isoformat() if isinstance(v, (dt.datetime, dt.date)) else v) for k, v in c.items() if v is not None}
        linhas.append({
            "aba": "Itens",
            "linha": r,
            "numero": int(c["A"]) if isinstance(c["A"], (int, float)) else None,
            "classe": txt(c["B"]),
            "grupo": txt(c["C"]),
            "descricao": txt(c["D"]),
            "prioridade": (txt(c["E"]) or "").lower() or None,
            "fase": txt(c["F"]),
            "pct_financiavel": num(c["G"], 4) or 0,
            "incluido": num(c["H"]) == 1,
            "unidade": txt(c["I"]),
            "quantidade": num(c["J"], 3) if precos else None,
            "precos": precos,
            "cenario": CENARIO.get(txt(c["N"])) if precos else None,
            "valor_fixo": None if precos else num(c["S"], 2),
            "valor_planilha": num(c["S"], 2),
            "base_contingencia": txt(c["B"]) in ("Obra principal", "Extras da obra"),
            "pago": pago,
            "observacao": txt(c["Z"]),
            "bruto": bruto,
        })
    with open(destino, "w", encoding="utf-8") as f:
        json.dump(linhas, f, ensure_ascii=False)
    print(f"{len(linhas)} linhas -> {destino}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
