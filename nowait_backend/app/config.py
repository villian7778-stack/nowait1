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
    # Payments are TEST MODE ONLY. With live (rzp_live_) keys real money would move, so the
    # backend refuses to talk to Razorpay unless this is explicitly set to true.
    RAZORPAY_ALLOW_LIVE: bool = False
    # Secret you choose when adding the webhook in the Razorpay dashboard (Settings -> Webhooks).
    # It is NOT the API key secret. Without it POST /payments/webhook answers 503.
    RAZORPAY_WEBHOOK_SECRET: str = ""
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
    # Shown on the public policy pages (/legal/...), which Google Play and Razorpay require.
    # Razorpay will ask for your registered business name and address - set them before launch.
    LEGAL_BUSINESS_NAME: str = "NOWAITT"
    SUPPORT_EMAIL: str = "nowaitt778@gmail.com"
    SUPPORT_PHONE: str = ""
    LEGAL_ADDRESS: str = ""
    LEGAL_JURISDICTION: str = ""  # e.g. "Akola, Maharashtra" - defaults to "India"
    # Cloudflare in front of the server (see PRODUCTION.md). Leave empty until the API is
    # reached through Cloudflare. When set, a Cloudflare Transform Rule must add this value to
    # every request as the X-Origin-Secret header: requests without it (someone going straight
    # to *.onrender.com, around Cloudflare) are refused, and rate limits use the visitor IP
    # Cloudflare puts in CF-Connecting-IP instead of the X-Forwarded-For header anyone can fake.
    CLOUDFLARE_ORIGIN_SECRET: str = ""
    # Forced app update. Each app build sends its build number (the +N in pubspec.yaml's
    # "version: 1.0.3+N"). Builds below the minimum get the "Update required" screen and every
    # API call answers 426 until the user installs the new version from the store. 0 = no minimum.
    # Raise it only AFTER the new build is live on the store, or nobody can use the app.
    APP_MIN_BUILD_ANDROID: int = 0
    APP_MIN_BUILD_IOS: int = 0
    APP_STORE_URL_ANDROID: str = "https://play.google.com/store/apps/details?id=com.nowaitt.nowaitt_app"
    APP_STORE_URL_IOS: str = ""  # e.g. https://apps.apple.com/app/id1234567890 once on the App Store

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
