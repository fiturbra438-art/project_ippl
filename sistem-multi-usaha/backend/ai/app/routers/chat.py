from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.ai import ChatAiRequest
from app.security import Claims, get_claims
from app.services.insight_ai import (
    ConversationNotFound,
    ProviderUnavailable,
    QuotaExceeded,
    build_reply,
)

router = APIRouter()


@router.post("/chat")
def chat_ai(
    payload: ChatAiRequest,
    claims: Claims = Depends(get_claims),
    db: Session = Depends(get_db),
):
    try:
        data = build_reply(db, claims, payload.chat_message(), payload.conversation_id)
    except QuotaExceeded:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Kuota pertanyaan AI Anda telah habis.")
    except ConversationNotFound:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Percakapan tidak ditemukan.")
    except ProviderUnavailable:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Layanan AI tidak tersedia.")
    except Exception:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Permintaan AI gagal diproses.")

    return {**data, "status": "success", "message": "Berhasil dijawab oleh AI.", "data": data}


@router.get("/conversations")
def list_conversations(claims: Claims = Depends(get_claims), db: Session = Depends(get_db)):
    rows = db.execute(text("""
        SELECT id, title, waktu_mulai AS created_at FROM chat_sessions
        WHERE owner_id = :owner_id ORDER BY id DESC LIMIT 100
    """), {"owner_id": claims.owner_id}).mappings().all()
    return {"conversations": [dict(row) for row in rows]}


@router.get("/conversations/{conversation_id}/messages")
def list_messages(conversation_id: int, claims: Claims = Depends(get_claims), db: Session = Depends(get_db)):
    owned = db.execute(text("""
        SELECT id FROM chat_sessions WHERE id = :id AND owner_id = :owner_id
    """), {"id": conversation_id, "owner_id": claims.owner_id}).scalar_one_or_none()
    if owned is None:
        raise HTTPException(status_code=404, detail="Percakapan tidak ditemukan.")
    rows = db.execute(text("""
        SELECT id, peran AS role, isi AS content, waktu AS created_at
        FROM chat_messages WHERE session_id = :id ORDER BY id
    """), {"id": conversation_id}).mappings().all()
    return {"messages": [dict(row) for row in rows]}
