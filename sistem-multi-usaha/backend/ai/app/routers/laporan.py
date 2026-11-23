from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.ai import ApiResponse
from app.security import Claims, ensure_owner, get_claims
from app.services.anomaly import detect_anomalies

router = APIRouter()


@router.get("/anomali", response_model=ApiResponse)
def get_anomali(
    claims: Claims = Depends(get_claims),
    db: Session = Depends(get_db),
):
    ensure_owner(claims)
    data = detect_anomalies(db, claims.owner_id)
    return ApiResponse(
        status="success",
        message=f"Deteksi anomali selesai. Ditemukan {len(data)} anomali bisnis.",
        data=data,
    )
