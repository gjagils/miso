"""Kwaliteitsdrempel: onze koppeling tegen AH's eigen productkeuzes (tests/data/ah_bar.txt).

Draait offline op de opgeslagen zoekresultaten. Verbetert de score, verhoog dan de drempels hier.
Vernieuwen met echte AH-data: `python -m tools.eval_bar --live`.
"""
import asyncio

from tools.eval_bar import run

MIN_GOOD_PCT = 93.0     # gelijk of zelfde soort als AH (2026-10-08 ronde 3: 94.2)
MIN_LINKED_PCT = 98.0   # ingrediënten met een product (ronde 3: 99.0)
MIN_QTY_PCT = 90.0      # aantal verpakkingen gelijk aan AH (2026-10-08: 94.8)


def test_matching_beats_quality_bar():
    score = asyncio.run(run(live=False, save=False))["score"]
    assert score["goed_pct"] >= MIN_GOOD_PCT, score
    assert score["gekoppeld_pct"] >= MIN_LINKED_PCT, score
    assert score["aantal_goed_pct"] >= MIN_QTY_PCT, score
