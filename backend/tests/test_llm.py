"""Relatieve modelkeuze: familie -> nieuwste model, 'claude-...' = vast, terugval zonder API."""
import asyncio
from datetime import datetime
from types import SimpleNamespace

from app import llm


def _m(id_, year):
    return SimpleNamespace(id=id_, created_at=datetime(year, 1, 1))


def test_newest_in_family():
    models = [_m("claude-haiku-4-5", 2025), _m("claude-haiku-5", 2027), _m("claude-sonnet-5-5", 2026),
              _m("claude-opus-5-5", 2026)]
    assert llm.newest_in_family(models, "haiku") == "claude-haiku-5"
    assert llm.newest_in_family(models, "sonnet") == "claude-sonnet-5-5"
    assert llm.newest_in_family(models, "mistral") is None


def test_pinned_and_fallback(monkeypatch):
    llm._cache.clear()
    monkeypatch.setattr(llm.settings, "anthropic_model", "claude-sonnet-5")
    assert asyncio.run(llm.model("slim")) == "claude-sonnet-5"  # vastgezet

    class Broken:
        def __init__(self, **kw):
            raise RuntimeError("geen netwerk")

    monkeypatch.setattr(llm.anthropic, "AsyncAnthropic", Broken)
    monkeypatch.setattr(llm.settings, "anthropic_model_fast", "haiku")
    assert asyncio.run(llm.model("snel")) == llm.FALLBACK["snel"]
