from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    anthropic_api_key: str = ""
    # Twee niveaus i.p.v. vaste modellen: "slim" voor recepten uitlezen (foto's, rommelige pagina's),
    # "snel" (goedkoop) voor korte JSON-taken: gezondheidsprofiel, glutenvrij-voorstel, wensen per dag.
    # Familie ("sonnet", "haiku", "opus") = altijd het nieuwste model daarvan; "claude-..." = precies dat model.
    anthropic_model: str = "sonnet"  # slim (ANTHROPIC_MODEL)
    anthropic_model_fast: str = "haiku"  # snel (ANTHROPIC_MODEL_FAST)
    database_url: str = "sqlite:///./data/ahcommunicator.db"
    log_level: str = "INFO"
    # Gedeelde pincode voor het gezin; leeg = geen beveiliging (alleen lokaal gebruiken!)
    app_pin: str = ""

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()
