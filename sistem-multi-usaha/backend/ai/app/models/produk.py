from datetime import datetime
from decimal import Decimal
from sqlalchemy import CheckConstraint, ForeignKey, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, TimestampMixin
from app.models.enums import TipeMovement, pg_enum
from app.models.usaha import UANG


class Product(TimestampMixin, Base):
    __tablename__ = "products"
    __table_args__ = (UniqueConstraint("owner_id", "sku", name="uq_product_owner_sku"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    sku: Mapped[str] = mapped_column(String(50))
    nama: Mapped[str] = mapped_column(String(150))
    kategori: Mapped[str | None] = mapped_column(String(80))
    harga_beli: Mapped[Decimal] = mapped_column(UANG)
    harga_jual: Mapped[Decimal] = mapped_column(UANG)
    satuan: Mapped[str] = mapped_column(String(20), default="pcs")


class Inventory(TimestampMixin, Base):
    __tablename__ = "inventories"
    __table_args__ = (UniqueConstraint("unit_id", "product_id", name="uq_inventory_unit_product"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    unit_id: Mapped[int] = mapped_column(ForeignKey("business_units.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id"), index=True)
    qty: Mapped[int] = mapped_column(default=0)
    min_stock: Mapped[int] = mapped_column(default=0)
    lokasi_rak: Mapped[str | None] = mapped_column(String(50))

    product = relationship("Product")
    movements = relationship("StockMovement", back_populates="inventory")


class StockMovement(TimestampMixin, Base):
    """masuk: unit_tujuan terisi | keluar: unit_asal terisi | transfer: keduanya."""
    __tablename__ = "stock_movements"
    __table_args__ = (
        CheckConstraint(
            "(tipe = 'masuk' AND unit_tujuan_id IS NOT NULL AND unit_asal_id IS NULL) OR "
            "(tipe = 'keluar' AND unit_asal_id IS NOT NULL AND unit_tujuan_id IS NULL) OR "
            "(tipe = 'transfer' AND unit_asal_id IS NOT NULL AND unit_tujuan_id IS NOT NULL "
            "AND unit_asal_id <> unit_tujuan_id)",
            name="ck_movement_unit_sesuai_tipe",
        ),
        CheckConstraint("qty > 0", name="ck_movement_qty_positif"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    inventory_id: Mapped[int] = mapped_column(ForeignKey("inventories.id"), index=True)
    tipe: Mapped[TipeMovement] = mapped_column(pg_enum(TipeMovement, "tipe_movement"))
    qty: Mapped[int]
    tanggal: Mapped[datetime] = mapped_column(server_default=func.now())
    unit_asal_id: Mapped[int | None] = mapped_column(ForeignKey("business_units.id"))
    unit_tujuan_id: Mapped[int | None] = mapped_column(ForeignKey("business_units.id"))
    dicatat_oleh: Mapped[int | None] = mapped_column(ForeignKey("users.id"))

    inventory = relationship("Inventory", back_populates="movements")
