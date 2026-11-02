import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.orm import Session
from fastapi import Depends

from app.database import get_db

app = FastAPI(
    title="Sistem Manajemen Multi-Usaha API",
    description="Backend API untuk sistem manajemen multi-usaha",
    version="1.0.0",
)

cors_env = os.getenv("CORS_ORIGIN", "http://localhost:8000,http://127.0.0.1:8000,http://localhost:3000")
allowed_origins = [orig.strip() for orig in cors_env.split(",") if orig.strip()]

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins if allowed_origins else ["*"],
    allow_credentials=True if allowed_origins and "*" not in allowed_origins else False,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def root():
    return {"message": "Selamat datang di Sistem Manajemen Multi-Usaha API"}

@app.get("/health")
def health(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    return {"status": "ok", "database": "terhubung"}
