import os
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL belum diatur. Buat file .env (lihat .env.example).")

JWT_SECRET = os.getenv("JWT_SECRET", "")
if not JWT_SECRET:
    raise RuntimeError(
        "JWT_SECRET belum diatur. Gunakan nilai yang sama dengan Core Rust "
        "(lihat .env.example) agar token login dapat diverifikasi."
    )

CORS_ORIGIN = os.getenv(
    "CORS_ORIGIN",
    "http://localhost:8000,http://127.0.0.1:8000,http://localhost:8001,http://localhost:3000",
)

PORT = int(os.getenv("PORT", "8001"))
