from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.ai import ApiResponse, ChatAiRequest
from app.security import Claims, get_claims
from app.services.insight_ai import QuotaExceeded, build_reply

router = APIRouter()


@router.post("/chat", response_model=ApiResponse)
def chat_ai(
    payload: ChatAiRequest,
    claims: Claims = Depends(get_claims),
    db: Session = Depends(get_db),
):
    try:
        data = build_reply(db, claims, payload.pesan)
    except QuotaExceeded:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Kuota pertanyaan AI Anda telah habis. Silakan hubungi admin "
                "atau upgrade paket Anda."
            ),
        )

    return ApiResponse(
        status="success",
        message="Berhasil dijawab oleh Python AI Analytics Service.",
        data=data,
    )
