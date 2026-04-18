from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "STOX Inventory API"
    app_version: str = "1.0.0"
    api_prefix: str = "/api/v1"
    debug: bool = True
    local_only_mode: bool = Field(default=False, alias="LOCAL_ONLY_MODE")

    database_url: str = Field(
        default="postgresql+psycopg://postgres:postgres@localhost:5432/stox_db",
        alias="DATABASE_URL",
    )
    db_connect_timeout_seconds: int = Field(default=5, alias="DB_CONNECT_TIMEOUT_SECONDS")
    create_tables_on_startup: bool = Field(default=False, alias="CREATE_TABLES_ON_STARTUP")

    frontend_origin: str = Field(default="http://localhost:3000", alias="FRONTEND_ORIGIN")
    frontend_origins: str = Field(default="", alias="FRONTEND_ORIGINS")
    jwt_secret_key: str = Field(default="change-me-in-production", alias="JWT_SECRET_KEY")
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = Field(default=15, alias="ACCESS_TOKEN_EXPIRE_MINUTES")
    refresh_token_expire_days: int = Field(default=7, alias="REFRESH_TOKEN_EXPIRE_DAYS")
    login_challenge_expire_minutes: int = Field(default=5, alias="LOGIN_CHALLENGE_EXPIRE_MINUTES")
    supabase_url: str = Field(default="", alias="SUPABASE_URL")
    supabase_anon_key: str = Field(default="", alias="SUPABASE_ANON_KEY")

    # Local Backup/Failover DB Settings
    local_db_user: str = Field(default="postgres", alias="LOCAL_DB_USER")
    local_db_password: str = Field(default="", alias="LOCAL_DB_PASSWORD")
    local_db_name: str = Field(default="stox_db", alias="LOCAL_DB_NAME")
    local_db_port: int = Field(default=5432, alias="LOCAL_DB_PORT")

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    @property
    def parsed_frontend_origins(self) -> list[str]:
        origins = [self.frontend_origin.strip()] if self.frontend_origin.strip() else []
        if self.frontend_origins.strip():
            origins.extend(origin.strip() for origin in self.frontend_origins.split(",") if origin.strip())

        # Keep ordering stable while removing duplicates.
        deduped: list[str] = []
        seen: set[str] = set()
        for origin in origins:
            if origin not in seen:
                seen.add(origin)
                deduped.append(origin)
        return deduped


@lru_cache
def get_settings() -> Settings:
    return Settings()
