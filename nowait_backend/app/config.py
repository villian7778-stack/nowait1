from typing import List

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    SUPABASE_URL: str
    SUPABASE_SERVICE_KEY: str
    SUPABASE_ANON_KEY: str
    SUPABASE_JWT_SECRET: str
    DEMO_MODE: bool = True          # Set False in production
    DEMO_OTP: str = "123456"
    DEMO_PASSWORD: str = "NowaitDemo#2024"
    # Comma-separated list of allowed CORS origins.
    # Default "*" is safe for a mobile-only API; restrict to your domain in web deployments.
    ALLOWED_ORIGINS: str = "*"

    @property
    def cors_origins(self) -> List[str]:
        if self.ALLOWED_ORIGINS.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",") if o.strip()]

    class Config:
        env_file = ".env"
        extra = "ignore"  # silently drop unknown keys (e.g. GOOGLE_MAP_KEY used by Flutter)


settings = Settings()
