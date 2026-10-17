import enum
from sqlalchemy import Enum as SAEnum


def pg_enum(enum_cls, name):
    """Disimpan sebagai VARCHAR + CHECK constraint (lebih mudah diubah
    lewat migrasi dibanding enum native PostgreSQL)."""
    return SAEnum(
        enum_cls,
        name=name,
        native_enum=False,
        length=30,
        create_constraint=False,
        values_callable=lambda e: [m.value for m in e],
    )


class Role(str, enum.Enum):
    OWNER = "owner"
    MANAGER = "manager"
    CASHIER = "cashier"
    WAREHOUSE_ADMIN = "warehouse_admin"


class KlasifikasiBCG(str, enum.Enum):
    CASH_COW = "cash_cow"
    STAR = "star"
    QUESTION_MARK = "question_mark"
    DOG = "dog"


class StatusAdvice(str, enum.Enum):
    PENDING = "pending"
    DISETUJUI = "disetujui"
    DITOLAK = "ditolak"


class JenisCashFlow(str, enum.Enum):
    MASUK = "masuk"
    KELUAR = "keluar"


class TipeMovement(str, enum.Enum):
    MASUK = "masuk"
    KELUAR = "keluar"
    TRANSFER = "transfer"


class StatusTransaksi(str, enum.Enum):
    SELESAI = "selesai"
    VOID = "void"


class Severity(str, enum.Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


class StatusAlert(str, enum.Enum):
    BARU = "baru"
    SELESAI = "selesai"
    ESKALASI = "eskalasi"


class StatusReallocation(str, enum.Enum):
    PENDING = "pending"
    DISETUJUI = "disetujui"
    DIEKSEKUSI = "dieksekusi"
    DITOLAK = "ditolak"


class PeranChat(str, enum.Enum):
    USER = "user"
    ASSISTANT = "assistant"
