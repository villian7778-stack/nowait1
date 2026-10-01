import os
from typing import List

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    SUPABASE_URL: str
    SUPABASE_SERVICE_KEY: str
    SUPABASE_ANON_KEY: str
    SUPABASE_JWT_SECRET: str
    # Comma-separated list of allowed browser origins. The mobile app does not use CORS
    # (CORS only applies to browsers), so the default is "none". Set ALLOWED_ORIGINS=*
    # in a local .env only if you run the Flutter web build against this API.
    ALLOWED_ORIGINS: str = ""
    # "production" hides /docs, /redoc and /openapi.json. Render sets RENDER=true
    # automatically, so a Render deploy counts as production without any extra config.
    ENVIRONMENT: str = ""
    GOOGLE_MAP_KEY: str = ""
    RAZORPAY_KEY_ID: str = ""
    RAZORPAY_KEY_SECRET: str = ""
    # Deep link the app registers (AndroidManifest intent-filter) to catch the
    # password-recovery callback. Supabase embeds this in the reset email link.
    PASSWORD_RESET_REDIRECT_URL: str = "io.nowait.app://auth-callback"
    # Admin panel (/nowaitt_778admin) login — must be set in .env, no default.
    ADMIN_USERNAME: str = "778Admin"
    ADMIN_PASSWORD: str = ""
    # Key used to hash emails / mobile numbers in trial_claims (the "one free month per
    # person" record). Set a long random value in .env and never change it afterwards:
    # changing it makes every earlier claim unrecognisable, so people could claim again.
    TRIAL_HASH_KEY: str = "nowait-free-trial-v1"

    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT.strip().lower() == "production" or os.getenv("RENDER", "").lower() == "true"

    @property
    def cors_origins(self) -> List[str]:
        if self.ALLOWED_ORIGINS.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",") if o.strip()]

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()
