from datetime import datetime
from sqlalchemy import create_engine, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

from app.config import DATABASE_URL

# Pastikan menggunakan driver psycopg (versi 3)
db_url = DATABASE_URL
if db_url.startswith("postgresql://"):
    db_url = db_url.replace("postgresql://", "postgresql+psycopg://", 1)

engine = create_engine(db_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


class TimestampMixin:
    """created_at di semua tabel (audit + time series)."""
    created_at: Mapped[datetime] = mapped_column(
        server_default=func.now(), nullable=False
    )


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
