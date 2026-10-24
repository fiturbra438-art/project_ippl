from sqlalchemy import Column, ForeignKey, String, Table, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, TimestampMixin
from app.models.enums import Role, pg_enum

# Relasi "mengelola 1..*": manager/kasir/admin gudang bisa bertugas di banyak unit
user_units = Table(
    "user_units",
    Base.metadata,
    Column("user_id", ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("unit_id", ForeignKey("business_units.id", ondelete="CASCADE"), primary_key=True),
)


class User(TimestampMixin, Base):
    """Single table inheritance: Owner/Manager/Cashier/WarehouseAdmin = kolom role."""
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
    nama: Mapped[str] = mapped_column(String(100))
    email: Mapped[str] = mapped_column(String(150), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[Role] = mapped_column(pg_enum(Role, "role"))
    aktif: Mapped[bool] = mapped_column(Boolean, default=True)
    nama_perusahaan: Mapped[str | None] = mapped_column(String(150))  # khusus owner

    unit_dimiliki = relationship("BusinessUnit", back_populates="owner")
    unit_ditugaskan = relationship("BusinessUnit", secondary=user_units, back_populates="staf")
