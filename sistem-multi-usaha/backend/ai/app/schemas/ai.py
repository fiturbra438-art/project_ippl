from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, Field, model_validator


class ChatAiRequest(BaseModel):
    message: Optional[str] = Field(default=None, min_length=1, max_length=2000)
    pesan: Optional[str] = Field(default=None, min_length=1, max_length=2000)
    conversation_id: Optional[int] = Field(default=None, gt=0)

    @model_validator(mode="after")
    def validate_message(self):
        if not (self.message or self.pesan or "").strip():
            raise ValueError("message is required")
        if self.message and self.pesan and self.message != self.pesan:
            raise ValueError("message and pesan must match")
        return self

    def chat_message(self) -> str:
        value = self.message or self.pesan
        if value is None:
            raise ValueError("message is required")
        return value


class ChatAiResponse(BaseModel):
    balasan: str
    sumber: str
    sisa_kuota_ai: int


class ForecastPoint(BaseModel):
    tanggal: date
    prediksi_penjualan: float
    batas_bawah: float
    batas_atas: float


class ForecastResponse(BaseModel):
    unit_id: int
    nama_unit: str
    horizon_hari: int
    tren: str
    rekomendasi_stok: str
    proyeksi: list[ForecastPoint]


class ProductForecastPoint(BaseModel):
    tanggal: date
    prediksi_qty: float
    status_risiko: str


class ProductForecast(BaseModel):
    product_id: int
    nama_produk: str
    stok_saat_ini: int
    total_prediksi: float
    status_risiko: str
    proyeksi: list[ProductForecastPoint]


class ProductForecastResponse(BaseModel):
    unit_id: int
    nama_unit: str
    horizon_hari: int
    items: list[ProductForecast]


class ReallocationItem(BaseModel):
    id: int
    product_id: int
    nama_produk: str
    unit_sumber_id: int
    unit_sumber: str
    unit_tujuan_id: int
    unit_tujuan: str
    jumlah_pindah: int
    alasan_ai: str
    estimasi_hemat_biaya: float


class AnomaliItem(BaseModel):
    id: int
    unit_id: int
    unit_kasus: str
    unit_pembanding: str
    judul: str
    tingkat_keparahan: str
    deskripsi: str
    potensi_kerugian: str
    waktu_deteksi: datetime


class PortfolioItem(BaseModel):
    id: int
    nama_usaha: str
    kategori: str
    growth_rate: float
    market_share: float
    arus_kas: float
    rekomendasi: str


class PortfolioResponse(BaseModel):
    items: list[PortfolioItem]
    ringkasan: dict[str, int]
    kebijakan_alokasi: list[str]


class WhatIfRequest(BaseModel):
    unit_sumber_id: int
    unit_tujuan_id: int
    persen_alokasi: float = Field(default=30, ge=0, le=100)


class WhatIfResponse(BaseModel):
    unit_sumber: str
    unit_tujuan: str
    surplus_kas_sumber: float
    persen_alokasi: float
    modal_dialokasikan: float
    proyeksi_kenaikan_omzet: float
    proyeksi_pertumbuhan_persen: float
    catatan: str


class ApiResponse(BaseModel):
    status: str
    message: str
    data: Optional[object] = None
