from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.config import CORS_ORIGIN
from app.database import get_db
from app.routers import chat, forecast, laporan, portofolio

app = FastAPI(
    title="Sistem Manajemen Multi-Usaha - AI Service",
    description="Microservice AI untuk chatbot, forecasting, anomali, dan portofolio.",
    version="1.0.0",
)

allowed_origins = [origin.strip() for origin in CORS_ORIGIN.split(",") if origin.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins if allowed_origins else ["*"],
    allow_credentials=True if allowed_origins and "*" not in allowed_origins else False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(HTTPException)
async def http_exception_handler(_: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"status": "error", "message": str(exc.detail), "data": None},
    )


@app.get("/")
def root():
    return {"message": "Selamat datang di Multi-Usaha AI Service"}


@app.get("/health")
def health(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    return {"status": "ok", "database": "terhubung"}


app.include_router(chat.router, prefix="/api/ai", tags=["AI Chat"])
app.include_router(forecast.router, prefix="/api/ai", tags=["AI Forecasting"])
app.include_router(laporan.router, prefix="/api/ai", tags=["AI Anomali"])
app.include_router(portofolio.router, prefix="/api/ai", tags=["AI Portofolio"])
