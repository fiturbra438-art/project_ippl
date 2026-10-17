from datetime import date, datetime
from decimal import Decimal
from sqlalchemy import CheckConstraint, ForeignKey, Index, Numeric, String, Text, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, TimestampMixin
from app.models.enums import (
    JenisCashFlow, KlasifikasiBCG, StatusAdvice, pg_enum,
)
from app.models.pengguna import user_units

UANG = Numeric(14, 2)


class BusinessUnit(TimestampMixin, Base):
    """Gudang juga dicatat sebagai unit dengan jenis_usaha = 'gudang'."""
    __tablename__ = "business_units"

    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    nama: Mapped[str] = mapped_column(String(100))
    jenis_usaha: Mapped[str] = mapped_column(String(50))
    lokasi: Mapped[str | None] = mapped_column(String(200))
    kategori_portofolio: Mapped[KlasifikasiBCG | None] = mapped_column(
        pg_enum(KlasifikasiBCG, "kategori_portofolio")
    )
    status: Mapped[bool] = mapped_column(Boolean, default=True)

    owner = relationship("User", back_populates="unit_dimiliki")
    staf = relationship("User", secondary=user_units, back_populates="unit_ditugaskan")
    cash_flows = relationship("CashFlow", back_populates="unit")


class CashFlow(TimestampMixin, Base):
    __tablename__ = "cash_flows"
    __table_args__ = (Index("ix_cash_flows_unit_tanggal", "unit_id", "tanggal"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    unit_id: Mapped[int] = mapped_column(ForeignKey("business_units.id"))
    tanggal: Mapped[date]
    jenis: Mapped[JenisCashFlow] = mapped_column(pg_enum(JenisCashFlow, "jenis_cashflow"))
    kategori: Mapped[str] = mapped_column(String(80))
    jumlah: Mapped[Decimal] = mapped_column(UANG)

    unit = relationship("BusinessUnit", back_populates="cash_flows")


class PortfolioAnalysis(TimestampMixin, Base):
    __tablename__ = "portfolio_analyses"

    id: Mapped[int] = mapped_column(primary_key=True)
    unit_id: Mapped[int] = mapped_column(ForeignKey("business_units.id"), index=True)
    periode: Mapped[date]
    klasifikasi: Mapped[KlasifikasiBCG] = mapped_column(pg_enum(KlasifikasiBCG, "klasifikasi_bcg"))
    risk_score: Mapped[float]
    liquidity_ratio: Mapped[float]
    growth_rate: Mapped[float]

    saran: Mapped[list["CapitalAllocationAdvice"]] = relationship(
        back_populates="analisis", cascade="all, delete-orphan"
    )


class CapitalAllocationAdvice(TimestampMixin, Base):
    __tablename__ = "capital_allocation_advices"
    __table_args__ = (CheckConstraint("unit_sumber_id <> unit_tujuan_id", name="ck_advice_beda_unit"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    analysis_id: Mapped[int] = mapped_column(
        ForeignKey("portfolio_analyses.id", ondelete="CASCADE"), index=True
    )
    unit_sumber_id: Mapped[int] = mapped_column(ForeignKey("business_units.id"))
    unit_tujuan_id: Mapped[int] = mapped_column(ForeignKey("business_units.id"))
    persentase: Mapped[float]
    nominal: Mapped[Decimal] = mapped_column(UANG)
    alasan: Mapped[str | None] = mapped_column(Text)
    status: Mapped[StatusAdvice] = mapped_column(
        pg_enum(StatusAdvice, "status_advice"), default=StatusAdvice.PENDING
    )

    analisis = relationship("PortfolioAnalysis", back_populates="saran")
