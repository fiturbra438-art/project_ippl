from __future__ import annotations

from statistics import median

from sqlalchemy import text
from sqlalchemy.orm import Session


def _rekomendasi(kategori: str) -> str:
    mapping = {
        "Star": "Prioritaskan suplai stok dan pemasaran untuk mempertahankan pertumbuhan tinggi.",
        "Cash Cow": "Gunakan surplus kas untuk mendanai unit Star atau Question Mark.",
        "Question Mark": "Uji pasar secara bertahap; tambah modal hanya bila growth konsisten.",
        "Dog": "Evaluasi efisiensi biaya; pertimbangkan divestasi bila tidak membaik dalam 2 kuartal.",
    }
    return mapping.get(kategori, "Tinjau kembali kinerja unit ini.")


def _unit_rows(db: Session, owner_id: int) -> list[dict]:
    rows = db.execute(
        text(
            """
            WITH current_period AS (
                SELECT t.unit_id, SUM(t.total)::float AS total
                FROM transactions t
                WHERE t.status = 'selesai'
                  AND t.tanggal >= CURRENT_DATE - INTERVAL '30 days'
                GROUP BY t.unit_id
            ), previous_period AS (
                SELECT t.unit_id, SUM(t.total)::float AS total
                FROM transactions t
                WHERE t.status = 'selesai'
                  AND t.tanggal >= CURRENT_DATE - INTERVAL '60 days'
                  AND t.tanggal < CURRENT_DATE - INTERVAL '30 days'
                GROUP BY t.unit_id
            )
            SELECT b.id,
                   b.nama,
                   b.pendapatan_bulan_ini::float AS pendapatan,
                   b.pengeluaran_bulan_ini::float AS pengeluaran,
                   COALESCE(b.pertumbuhan_persen, 0)::float AS pertumbuhan,
                   COALESCE(c.total, 0)::float AS omzet_30_hari,
                   COALESCE(p.total, 0)::float AS omzet_30_hari_lalu
            FROM business_units b
            LEFT JOIN current_period c ON c.unit_id = b.id
            LEFT JOIN previous_period p ON p.unit_id = b.id
            WHERE b.owner_id = :owner_id
            ORDER BY b.id
            """
        ),
        {"owner_id": owner_id},
    ).mappings().all()
    return [dict(row) for row in rows]


def generate_portfolio(db: Session, owner_id: int) -> dict:
    units = _unit_rows(db, owner_id)
    if not units:
        return {
            "items": [],
            "ringkasan": {"Star": 0, "Cash Cow": 0, "Question Mark": 0, "Dog": 0},
            "kebijakan_alokasi": [
                "Belum ada unit usaha. Tambahkan unit terlebih dahulu untuk analisis portofolio."
            ],
        }

    growth_values = []
    for unit in units:
        previous = unit["omzet_30_hari_lalu"]
        current = unit["omzet_30_hari"]
        if previous > 0:
            growth = (current - previous) / previous * 100
        else:
            growth = unit["pertumbuhan"]
        unit["growth_rate"] = round(growth, 2)
        growth_values.append(growth)

    total_revenue = sum(max(0.0, unit["omzet_30_hari"]) for unit in units)
    average_revenue = total_revenue / len(units) if units else 0.0
    growth_threshold = median(growth_values) if growth_values else 0.0

    items = []
    summary = {"Star": 0, "Cash Cow": 0, "Question Mark": 0, "Dog": 0}
    for unit in units:
        market_share = (
            unit["omzet_30_hari"] / average_revenue if average_revenue > 0 else 0.0
        )
        high_growth = unit["growth_rate"] >= growth_threshold
        high_share = market_share >= 1.0

        if high_growth and high_share:
            kategori = "Star"
        elif not high_growth and high_share:
            kategori = "Cash Cow"
        elif high_growth and not high_share:
            kategori = "Question Mark"
        else:
            kategori = "Dog"

        summary[kategori] += 1
        items.append(
            {
                "id": unit["id"],
                "nama_usaha": unit["nama"],
                "kategori": kategori,
                "growth_rate": round(unit["growth_rate"], 1),
                "market_share": round(market_share, 2),
                "arus_kas": round(unit["pendapatan"] - unit["pengeluaran"], 2),
                "rekomendasi": _rekomendasi(kategori),
            }
        )

    policies = [
        f"Alokasikan surplus kas dari {summary['Cash Cow']} unit Cash Cow ke "
        f"{summary['Question Mark']} unit Question Mark secara bertahap.",
        f"Dukung ekspansi {summary['Star']} unit Star dengan prioritas stok dan pemasaran.",
        f"Tinjau ulang {summary['Dog']} unit Dog; beri tenggat 1-2 kuartal untuk perbaikan.",
    ]

    items.sort(key=lambda item: item["arus_kas"], reverse=True)
    return {
        "items": items,
        "ringkasan": summary,
        "kebijakan_alokasi": policies,
    }


def simulate_what_if(
    db: Session, owner_id: int, unit_sumber_id: int, unit_tujuan_id: int, persen: float
) -> dict | None:
    if unit_sumber_id == unit_tujuan_id:
        return None

    units = {row["id"]: row for row in _unit_rows(db, owner_id)}
    source = units.get(unit_sumber_id)
    target = units.get(unit_tujuan_id)
    if not source or not target:
        return None

    surplus = max(0.0, source["pendapatan"] - source["pengeluaran"])
    if surplus <= 0:
        surplus = max(0.0, source["omzet_30_hari"] * 0.2)

    allocation = surplus * (persen / 100.0)
    projected_revenue = allocation * 1.85
    projected_growth = 4.5 + (persen * 0.45)

    return {
        "unit_sumber": source["nama"],
        "unit_tujuan": target["nama"],
        "surplus_kas_sumber": round(surplus, 2),
        "persen_alokasi": persen,
        "modal_dialokasikan": round(allocation, 2),
        "proyeksi_kenaikan_omzet": round(projected_revenue, 2),
        "proyeksi_pertumbuhan_persen": round(projected_growth, 1),
        "catatan": (
            "Simulasi heuristik berbasis rasio modal-omzet historis. "
            "Gunakan sebagai bahan pertimbangan, bukan jaminan hasil."
        ),
    }
