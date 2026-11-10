from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.ai import ApiResponse, WhatIfRequest
from app.security import Claims, get_claims
from app.services.portofolio import generate_portfolio, simulate_what_if

router = APIRouter()


@router.get("/portfolio", response_model=ApiResponse)
def get_portfolio(
    claims: Claims = Depends(get_claims),
    db: Session = Depends(get_db),
):
    data = generate_portfolio(db, claims.owner_id)
    return ApiResponse(
        status="success",
        message="Analisis portofolio BCG berhasil dihitung.",
        data=data,
    )


@router.post("/what-if", response_model=ApiResponse)
def what_if(
    payload: WhatIfRequest,
    claims: Claims = Depends(get_claims),
    db: Session = Depends(get_db),
):
    data = simulate_what_if(
        db,
        claims.owner_id,
        payload.unit_sumber_id,
        payload.unit_tujuan_id,
        payload.persen_alokasi,
    )
    if data is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "Unit sumber/tujuan tidak valid. Pastikan keduanya milik bisnis "
                "Anda dan merupakan unit yang berbeda."
            ),
        )
    return ApiResponse(
        status="success",
        message="Simulasi what-if alokasi modal berhasil dihitung.",
        data=data,
    )
