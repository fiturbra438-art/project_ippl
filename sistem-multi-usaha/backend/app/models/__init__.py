# Import semua model agar terdaftar di Base.metadata (dibutuhkan Alembic)
from app.models.pengguna import User, user_units  # noqa: F401
from app.models.usaha import (  # noqa: F401
    BusinessUnit, CashFlow, PortfolioAnalysis, CapitalAllocationAdvice,
)
from app.models.produk import Product, Inventory, StockMovement  # noqa: F401
from app.models.transaksi import Transaction, TransactionItem  # noqa: F401
from app.models.analitik import (  # noqa: F401
    DemandForecast, ReallocationRecommendation, AnomalyAlert,
)
from app.models.chat import ChatSession, ChatMessage  # noqa: F401
