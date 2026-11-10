from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.security import Claims


class QuotaExceeded(Exception):
    pass


def _rupiah(value: float) -> str:
    return f"Rp {value:,.0f}".replace(",", ".")


def build_reply(db: Session, claims: Claims, pesan: str) -> dict:
    user = db.execute(
        text(
            "SELECT id, sisa_kuota_ai, nama_perusahaan, tier "
            "FROM users WHERE id = :owner_id"
        ),
        {"owner_id": claims.owner_id},
    ).mappings().first()

    if user and int(user["sisa_kuota_ai"] or 0) <= 0:
        raise QuotaExceeded

    if user:
        db.execute(
            text(
                "UPDATE users "
                "SET sisa_kuota_ai = GREATEST(COALESCE(sisa_kuota_ai, 250) - 1, 0) "
                "WHERE id = :owner_id"
            ),
            {"owner_id": claims.owner_id},
        )
        db.commit()

    remaining = int(user["sisa_kuota_ai"] or 250) - 1 if user else 250
    business_name = (
        user["nama_perusahaan"] if user and user["nama_perusahaan"] else "Grup Bisnis"
    )

    total_units = db.execute(
        text("SELECT COUNT(*) FROM business_units WHERE owner_id = :owner_id"),
        {"owner_id": claims.owner_id},
    ).scalar_one()

    total_revenue = db.execute(
        text(
            """
            SELECT COALESCE(SUM(t.total), 0)::float
            FROM transactions t
            JOIN business_units b ON b.id = t.unit_id
            WHERE b.owner_id = :owner_id AND t.status = 'selesai'
            """
        ),
        {"owner_id": claims.owner_id},
    ).scalar_one()

    total_products = db.execute(
        text("SELECT COUNT(*) FROM products WHERE owner_id = :owner_id"),
        {"owner_id": claims.owner_id},
    ).scalar_one()

    critical_products = db.execute(
        text(
            """
            SELECT p.nama, i.qty
            FROM inventories i
            JOIN products p ON p.id = i.product_id
            JOIN business_units b ON b.id = i.unit_id
            WHERE b.owner_id = :owner_id AND i.qty <= i.min_stock
            ORDER BY i.qty ASC
            LIMIT 5
            """
        ),
        {"owner_id": claims.owner_id},
    ).mappings().all()

    units = db.execute(
        text(
            """
            SELECT nama, jenis_usaha, kategori_portofolio,
                   pendapatan_bulan_ini::float AS pendapatan,
                   pengeluaran_bulan_ini::float AS pengeluaran
            FROM business_units
            WHERE owner_id = :owner_id
            ORDER BY nama
            """
        ),
        {"owner_id": claims.owner_id},
    ).mappings().all()

    weekly = db.execute(
        text(
            """
            SELECT COALESCE(SUM(t.total), 0)::float
            FROM transactions t
            JOIN business_units b ON b.id = t.unit_id
            WHERE b.owner_id = :owner_id
              AND t.status = 'selesai'
              AND t.tanggal >= CURRENT_DATE - INTERVAL '7 days'
            """
        ),
        {"owner_id": claims.owner_id},
    ).scalar_one()

    star_units = [
        unit["nama"]
        for unit in units
        if (unit["kategori_portofolio"] or "").strip().lower() == "star"
    ]
    unit_names = [
        f"- {unit['nama']} ({unit['jenis_usaha']}, "
        f"Kategori: {unit['kategori_portofolio'] or 'Umum'})"
        for unit in units
    ]

    query = pesan.lower()
    if any(word in query for word in ("omzet", "pendapatan", "penjualan", "laba")):
        if total_units == 0:
            reply = (
                "Belum ada unit usaha terdaftar. Daftarkan cabang terlebih dahulu "
                "agar saya dapat menghitung omzet."
            )
        else:
            reply = (
                f"Rekap {business_name}:\n"
                f"- Total omzet (semua transaksi selesai): {_rupiah(total_revenue)}\n"
                f"- Omzet 7 hari terakhir: {_rupiah(weekly)}\n"
                f"- Unit usaha aktif: {total_units}\n"
                f"- Produk terdaftar: {total_products}"
            )
    elif any(word in query for word in ("stok", "kritis", "gudang", "restok")):
        if not critical_products:
            reply = f"Inventaris aman. Seluruh {total_products} produk berada di atas batas minimum."
        else:
            lines = "\n".join(
                f"- {row['nama']} (sisa {row['qty']})" for row in critical_products
            )
            reply = (
                "Peringatan stok minimum:\n"
                f"{lines}\n"
                "Segera lakukan pengadaan atau mutasi stok dari cabang lain."
            )
    elif any(word in query for word in ("cabang", "unit", "toko", "usaha")):
        reply = (
            f"Daftar unit usaha {business_name}:\n" + "\n".join(unit_names)
            if unit_names
            else "Belum ada unit usaha yang tersimpan."
        )
    elif any(word in query for word in ("saran", "strategi", "alokasi", "modal")):
        stars = ", ".join(star_units) if star_units else "belum terpetakan"
        reply = (
            "Rekomendasi portofolio:\n"
            f"1. Unit Star ({stars}): prioritaskan suplai stok dan pemasaran.\n"
            "2. Alokasikan surplus kas Cash Cow ke unit Question Mark secara bertahap.\n"
            "3. Evaluasi unit Dog dan tetapkan tenggat perbaikan 1-2 kuartal."
        )
    elif any(word in query for word in ("prediksi", "forecast", "tren", "proyeksi")):
        reply = (
            "Gunakan menu Forecasting untuk proyeksi 7/30 hari per unit. "
            "Model memakai rata-rata bergerak, pola hari kerja, dan tren 90 hari "
            f"transaksi. Omzet 7 hari terakhir saat ini {_rupiah(weekly)}."
        )
    else:
        reply = (
            f"Halo! Saya asisten AI {business_name}. Saat ini tercatat "
            f"{total_units} unit usaha, {total_products} produk, dan total omzet "
            f"{_rupiah(total_revenue)}. Tanyakan soal omzet, stok, cabang, "
            "prediksi, atau strategi alokasi modal."
        )

    return {
        "balasan": reply,
        "sumber": "Python AI Analytics Service",
        "sisa_kuota_ai": max(remaining, 0),
    }
