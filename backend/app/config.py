from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    anthropic_api_key: str = ""
    # Twee niveaus i.p.v. vaste modellen: "slim" voor recepten uitlezen (foto's, rommelige pagina's),
    # "snel" (goedkoop) voor korte JSON-taken: gezondheidsprofiel, glutenvrij-voorstel, wensen per dag.
    anthropic_model: str = "claude-sonnet-5-5"  # slim (ANTHROPIC_MODEL)
    anthropic_model_fast: str = "claude-haiku-4-5"  # snel (ANTHROPIC_MODEL_FAST)
    database_url: str = "sqlite:///./data/ahcommunicator.db"
    log_level: str = "INFO"
    # Gedeelde pincode voor het gezin; leeg = geen beveiliging (alleen lokaal gebruiken!)
    app_pin: str = ""

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()
