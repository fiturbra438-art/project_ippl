from typing import Optional

import jwt
from fastapi import Depends, Header, HTTPException, status
from sqlalchemy import text
from sqlalchemy.orm import Session
from pydantic import BaseModel

from app.config import JWT_SECRET
from app.database import get_db


class Claims(BaseModel):
    sub: str
    user_id: int
    role: str
    owner_id: int
    tier: Optional[str] = None
    exp: int


def get_claims(authorization: str = Header(default=""), db: Session = Depends(get_db)) -> Claims:
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Akses ditolak: sertakan token JWT Bearer yang valid.",
        )

    token = authorization.removeprefix("Bearer ").strip()
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        claims = Claims(**payload)
        row = db.execute(text("""
            SELECT u.email, u.role, u.aktif, o.id AS owner_id, o.aktif AS owner_aktif, o.tier
            FROM users u JOIN users o ON o.id = CASE WHEN u.role = 'owner' THEN u.id ELSE u.owner_id END
            WHERE u.id = :user_id AND o.role = 'owner'
        """), {"user_id": claims.user_id}).mappings().first()
        if not row or not row["aktif"] or not row["owner_aktif"] or row["owner_id"] != claims.owner_id:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Akun tidak aktif atau sesi tidak lagi berlaku.")
        claims.sub = row["email"]
        claims.role = row["role"]
        claims.tier = row["tier"]
        return claims
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


def ensure_owner(claims: Claims) -> None:
    if claims.role != "owner":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Fitur ini hanya tersedia untuk owner.")


def ensure_unit_access(db: Session, claims: Claims, unit_id: int) -> None:
    allowed = db.execute(text("""
        SELECT EXISTS(SELECT 1 FROM business_units u
          WHERE u.id = :unit_id AND u.owner_id = :owner_id
            AND (:is_owner OR EXISTS(SELECT 1 FROM user_units uu
              WHERE uu.unit_id = u.id AND uu.user_id = :user_id)))
    """), {"unit_id": unit_id, "owner_id": claims.owner_id,
            "is_owner": claims.role == "owner", "user_id": claims.user_id}).scalar()
    if not allowed:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unit usaha tidak dapat diakses.")
