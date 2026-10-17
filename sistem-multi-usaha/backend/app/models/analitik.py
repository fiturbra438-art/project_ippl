from datetime import date, datetime
from decimal import Decimal
from sqlalchemy import CheckConstraint, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, TimestampMixin
from app.models.enums import Severity, StatusAlert, StatusReallocation, pg_enum
from app.models.usaha import UANG


class DemandForecast(TimestampMixin, Base):
    __tablename__ = "demand_forecasts"
    __table_args__ = (Index("ix_forecast_unit_product_periode", "unit_id", "product_id", "periode"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    unit_id: Mapped[int] = mapped_column(ForeignKey("business_units.id"))
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id"))
    periode: Mapped[date]
    prediksi_qty: Mapped[float]
    model_dipakai: Mapped[str] = mapped_column(String(30))  # Prophet / SARIMA / LSTM
    mape: Mapped[float | None]

    rekomendasi: Mapped[list["ReallocationRecommendation"]] = relationship(
        back_populates="forecast", cascade="all, delete-orphan"
    )


class ReallocationRecommendation(TimestampMixin, Base):
    __tablename__ = "reallocation_recommendations"
    __table_args__ = (CheckConstraint("unit_asal_id <> unit_tujuan_id", name="ck_realloc_beda_unit"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    forecast_id: Mapped[int] = mapped_column(
        ForeignKey("demand_forecasts.id", ondelete="CASCADE"), index=True
    )
    unit_asal_id: Mapped[int] = mapped_column(ForeignKey("business_units.id"))
    unit_tujuan_id: Mapped[int] = mapped_column(ForeignKey("business_units.id"))
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id"))
    qty: Mapped[int]
    estimasi_penghematan: Mapped[Decimal] = mapped_column(UANG, default=0)
    status: Mapped[StatusReallocation] = mapped_column(
        pg_enum(StatusReallocation, "status_reallocation"), default=StatusReallocation.PENDING
    )

    forecast = relationship("DemandForecast", back_populates="rekomendasi")


class AnomalyAlert(TimestampMixin, Base):
    __tablename__ = "anomaly_alerts"

    id: Mapped[int] = mapped_column(primary_key=True)
    unit_id: Mapped[int] = mapped_column(ForeignKey("business_units.id"), index=True)
    jenis: Mapped[str] = mapped_column(String(50))
    anomaly_score: Mapped[float]
    severity: Mapped[Severity] = mapped_column(pg_enum(Severity, "severity"))
    status: Mapped[StatusAlert] = mapped_column(
        pg_enum(StatusAlert, "status_alert"), default=StatusAlert.BARU
    )
    waktu_deteksi: Mapped[datetime]
