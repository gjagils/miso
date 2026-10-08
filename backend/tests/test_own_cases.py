"""Vaste gevallen uit de review van onze eigen (Mealie-)recepten: foute producten mogen niet terugkomen.

Offline op de opgeslagen zoekresultaten. Vernieuwen: `python -m tools.eval_own --live`.
"""
import asyncio

from tools.eval_own import run

MIN_OK = 49  # van 55 (2026-10-08 ronde 5)


def test_review_cases_stay_fixed():
    r = asyncio.run(run(live=False, save=False))
    assert r["ok"] >= MIN_OK, r["fails"]
