from typing import List

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    SUPABASE_URL: str
    SUPABASE_SERVICE_KEY: str
    SUPABASE_ANON_KEY: str
    SUPABASE_JWT_SECRET: str
    # Comma-separated list of allowed CORS origins.
    # Default "*" is safe for a mobile-only API; restrict to your domain in web deployments.
    ALLOWED_ORIGINS: str = "*"
    GOOGLE_MAP_KEY: str = ""
    RAZORPAY_KEY_ID: str = ""
    RAZORPAY_KEY_SECRET: str = ""
    # Deep link the app registers (AndroidManifest intent-filter) to catch the
    # password-recovery callback. Supabase embeds this in the reset email link.
    PASSWORD_RESET_REDIRECT_URL: str = "io.nowait.app://auth-callback"
    # Admin panel (/nowaitt_778admin) login — must be set in .env, no default.
    ADMIN_USERNAME: str = "778Admin"
    ADMIN_PASSWORD: str = ""

    @property
    def cors_origins(self) -> List[str]:
        if self.ALLOWED_ORIGINS.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",") if o.strip()]

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()
