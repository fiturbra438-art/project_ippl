from datetime import datetime
from sqlalchemy import ForeignKey, Text, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, TimestampMixin
from app.models.enums import PeranChat, pg_enum


class ChatSession(TimestampMixin, Base):
    __tablename__ = "chat_sessions"

    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    waktu_mulai: Mapped[datetime] = mapped_column(server_default=func.now())

    pesan = relationship(
        "ChatMessage", back_populates="sesi", cascade="all, delete-orphan",
        order_by="ChatMessage.waktu",
    )


class ChatMessage(TimestampMixin, Base):
    __tablename__ = "chat_messages"

    id: Mapped[int] = mapped_column(primary_key=True)
    session_id: Mapped[int] = mapped_column(
        ForeignKey("chat_sessions.id", ondelete="CASCADE"), index=True
    )
    peran: Mapped[PeranChat] = mapped_column(pg_enum(PeranChat, "peran_chat"))
    isi: Mapped[str] = mapped_column(Text)
    sumber_data: Mapped[dict | None] = mapped_column(JSONB)
    waktu: Mapped[datetime] = mapped_column(server_default=func.now())

    sesi = relationship("ChatSession", back_populates="pesan")
