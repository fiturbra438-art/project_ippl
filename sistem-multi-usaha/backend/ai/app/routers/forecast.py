from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.ai import ApiResponse
from app.security import Claims, get_claims
from app.services.forecasting import (
    generate_forecast,
    generate_product_forecast,
    generate_reallocation,
)

router = APIRouter()


@router.get("/forecast/{unit_id}", response_model=ApiResponse)
def get_forecast(
    unit_id: int,
    horizon: int = Query(default=7, ge=1, le=30),
    claims: Claims = Depends(get_claims),
    db: Session = Depends(get_db),
):
    data = generate_forecast(db, unit_id, claims.owner_id, horizon)
    if data is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Unit usaha tidak ditemukan atau bukan milik bisnis Anda.",
        )
    return ApiResponse(
        status="success",
        message="Forecasting berhasil dihitung dari histori transaksi PostgreSQL.",
        data=data,
    )


@router.get("/forecast/{unit_id}/products", response_model=ApiResponse)
def get_product_forecast(
    unit_id: int,
    horizon: int = Query(default=7, ge=1, le=30),
    claims: Claims = Depends(get_claims),
    db: Session = Depends(get_db),
):
    data = generate_product_forecast(db, unit_id, claims.owner_id, horizon)
    if data is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Unit usaha tidak ditemukan atau bukan milik bisnis Anda.",
        )
    return ApiResponse(
        status="success",
        message="Prediksi permintaan per produk berhasil dihitung.",
        data=data,
    )


@router.get("/reallocation", response_model=ApiResponse)
def get_reallocation(
    claims: Claims = Depends(get_claims),
    db: Session = Depends(get_db),
):
    data = generate_reallocation(db, claims.owner_id)
    return ApiResponse(
        status="success",
        message=f"Ditemukan {len(data)} rekomendasi realokasi stok.",
        data=data,
    )
