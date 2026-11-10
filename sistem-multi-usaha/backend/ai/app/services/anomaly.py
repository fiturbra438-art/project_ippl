from __future__ import annotations

from datetime import datetime

from sqlalchemy import text
from sqlalchemy.orm import Session


def _rupiah(value: float) -> str:
    return f"Rp {value:,.0f}".replace(",", ".")


def detect_anomalies(db: Session, owner_id: int) -> list[dict]:
    anomalies: list[dict] = []
    now = datetime.now()

    critical_rows = db.execute(
        text(
            """
            SELECT v.product_id,
                   v.unit_id,
                   v.nama_unit,
                   v.nama_produk,
                   v.stok_saat_ini,
                   v.batas_minimum,
                   v.kebutuhan_restok,
                   v.harga_beli::float AS harga_beli
            FROM view_produk_stok_kritis v
            JOIN business_units b ON b.id = v.unit_id
            WHERE b.owner_id = :owner_id
            """
        ),
        {"owner_id": owner_id},
    ).mappings().all()

    for row in critical_rows:
        potential_loss = float(row["kebutuhan_restok"] or 0) * float(
            row["harga_beli"] or 0
        )
        anomalies.append(
            {
                "id": len(anomalies) + 1,
                "unit_id": row["unit_id"],
                "unit_kasus": row["nama_unit"],
                "unit_pembanding": "Batas minimum stok",
                "judul": f"Stok Kritis: {row['nama_produk']}",
                "tingkat_keparahan": "TINGGI",
                "deskripsi": (
                    f"Stok {row['nama_produk']} tersisa {row['stok_saat_ini']} unit, "
                    f"di bawah batas minimum {row['batas_minimum']} unit. "
                    f"Kebutuhan restok minimal {row['kebutuhan_restok']} unit."
                ),
                "potensi_kerugian": _rupiah(potential_loss),
                "waktu_deteksi": now,
            }
        )

    deficit_rows = db.execute(
        text(
            """
            SELECT id, nama, pendapatan_bulan_ini::float AS pendapatan,
                   pengeluaran_bulan_ini::float AS pengeluaran
            FROM business_units
            WHERE owner_id = :owner_id
              AND pengeluaran_bulan_ini > pendapatan_bulan_ini
              AND pengeluaran_bulan_ini > 0
            """
        ),
        {"owner_id": owner_id},
    ).mappings().all()

    for row in deficit_rows:
        deficit = float(row["pengeluaran"]) - float(row["pendapatan"])
        anomalies.append(
            {
                "id": len(anomalies) + 1,
                "unit_id": row["id"],
                "unit_kasus": row["nama"],
                "unit_pembanding": "Target pendapatan bulanan",
                "judul": "Defisit Operasional Cabang",
                "tingkat_keparahan": "TINGGI" if deficit > 5_000_000 else "SEDANG",
                "deskripsi": (
                    f"Pengeluaran {_rupiah(float(row['pengeluaran']))} melebihi "
                    f"pendapatan {_rupiah(float(row['pendapatan']))}. "
                    f"Defisit {_rupiah(deficit)}."
                ),
                "potensi_kerugian": _rupiah(deficit),
                "waktu_deteksi": now,
            }
        )

    sales_rows = db.execute(
        text(
            """
            WITH recent AS (
                SELECT t.unit_id, SUM(t.total)::float AS total
                FROM transactions t
                WHERE t.status = 'selesai'
                  AND t.tanggal >= CURRENT_DATE - INTERVAL '7 days'
                GROUP BY t.unit_id
            ), previous AS (
                SELECT t.unit_id, SUM(t.total)::float AS total
                FROM transactions t
                WHERE t.status = 'selesai'
                  AND t.tanggal >= CURRENT_DATE - INTERVAL '14 days'
                  AND t.tanggal < CURRENT_DATE - INTERVAL '7 days'
                GROUP BY t.unit_id
            )
            SELECT b.id,
                   b.nama,
                   COALESCE(r.total, 0)::float AS recent_total,
                   COALESCE(p.total, 0)::float AS previous_total
            FROM business_units b
            LEFT JOIN recent r ON r.unit_id = b.id
            LEFT JOIN previous p ON p.unit_id = b.id
            WHERE b.owner_id = :owner_id
            """
        ),
        {"owner_id": owner_id},
    ).mappings().all()

    for row in sales_rows:
        recent = float(row["recent_total"] or 0)
        previous = float(row["previous_total"] or 0)
        if previous <= 0:
            continue
        change = (recent - previous) / previous
        if change >= -0.4:
            continue

        loss = previous - recent
        anomalies.append(
            {
                "id": len(anomalies) + 1,
                "unit_id": row["id"],
                "unit_kasus": row["nama"],
                "unit_pembanding": "7 hari sebelumnya",
                "judul": "Penurunan Penjualan Signifikan",
                "tingkat_keparahan": "TINGGI" if change <= -0.6 else "SEDANG",
                "deskripsi": (
                    f"Penjualan 7 hari terakhir {_rupiah(recent)} turun "
                    f"{abs(change) * 100:.1f}% dibanding periode sebelumnya "
                    f"{_rupiah(previous)}."
                ),
                "potensi_kerugian": _rupiah(loss),
                "waktu_deteksi": now,
            }
        )

    return anomalies
