from typing import Optional

import jwt
from fastapi import Header, HTTPException, status
from pydantic import BaseModel

from app.config import JWT_SECRET


class Claims(BaseModel):
    sub: str
    user_id: int
    role: str
    owner_id: int
    tier: Optional[str] = None
    exp: int


def get_claims(authorization: str = Header(default="")) -> Claims:
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Akses ditolak: sertakan token JWT Bearer yang valid.",
        )

    token = authorization.removeprefix("Bearer ").strip()
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        return Claims(**payload)
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token JWT telah kedaluwarsa. Silakan login kembali.",
        )
    except (jwt.PyJWTError, ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token JWT tidak valid.",
        )
