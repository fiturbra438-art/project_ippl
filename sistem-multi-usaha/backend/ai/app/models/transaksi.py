from datetime import datetime
from decimal import Decimal
from sqlalchemy import ForeignKey, Index, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, TimestampMixin
from app.models.enums import StatusTransaksi, pg_enum
from app.models.usaha import UANG


class Transaction(TimestampMixin, Base):
    __tablename__ = "transactions"
    __table_args__ = (Index("ix_transactions_unit_tanggal", "unit_id", "tanggal"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    unit_id: Mapped[int] = mapped_column(ForeignKey("business_units.id"))
    kasir_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    tanggal: Mapped[datetime] = mapped_column(server_default=func.now())
    total: Mapped[Decimal] = mapped_column(UANG, default=0)
    metode_bayar: Mapped[str] = mapped_column(String(30))
    status: Mapped[StatusTransaksi] = mapped_column(
        pg_enum(StatusTransaksi, "status_transaksi"), default=StatusTransaksi.SELESAI
    )

    items = relationship("TransactionItem", back_populates="transaksi", cascade="all, delete-orphan")


class TransactionItem(TimestampMixin, Base):
    __tablename__ = "transaction_items"

    id: Mapped[int] = mapped_column(primary_key=True)
    trx_id: Mapped[int] = mapped_column(ForeignKey("transactions.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id"), index=True)
    qty: Mapped[int]
    harga_satuan: Mapped[Decimal] = mapped_column(UANG)
    subtotal: Mapped[Decimal] = mapped_column(UANG)

    transaksi = relationship("Transaction", back_populates="items")
