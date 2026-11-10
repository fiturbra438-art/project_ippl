from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta
from statistics import mean, pstdev
from typing import Optional

from sqlalchemy import text
from sqlalchemy.orm import Session


def _unit_for_owner(db: Session, unit_id: int, owner_id: int) -> Optional[dict]:
    row = db.execute(
        text(
            "SELECT id, nama FROM business_units "
            "WHERE id = :unit_id AND owner_id = :owner_id"
        ),
        {"unit_id": unit_id, "owner_id": owner_id},
    ).mappings().first()
    return dict(row) if row else None


def _daily_series(values: dict[date, float], days: int) -> list[tuple[date, float]]:
    end = date.today()
    start = end - timedelta(days=days - 1)
    return [
        (start + timedelta(days=i), float(values.get(start + timedelta(days=i), 0.0)))
        for i in range(days)
    ]


def _ewma(values: list[float], alpha: float = 0.3) -> float:
    if not values:
        return 0.0
    result = float(values[0])
    for value in values[1:]:
        result = alpha * float(value) + (1 - alpha) * result
    return result


def _weekday_factors(series: list[tuple[date, float]]) -> dict[int, float]:
    buckets: dict[int, list[float]] = defaultdict(list)
    for day, value in series:
        buckets[day.weekday()].append(value)
    overall = mean([value for _, value in series]) if series else 0.0
    if overall <= 0:
        return {i: 1.0 for i in range(7)}
    factors = {}
    for weekday in range(7):
        values = buckets.get(weekday, [])
        factor = mean(values) / overall if values else 1.0
        factors[weekday] = max(0.65, min(1.45, factor))
    return factors


def _trend_label(series: list[tuple[date, float]]) -> tuple[str, float]:
    values = [value for _, value in series]
    if len(values) < 14 or mean(values) <= 0:
        return "Belum ada data", 0.0

    recent = mean(values[-7:])
    previous = mean(values[-14:-7])
    if previous <= 0:
        if recent <= 0:
            return "Belum ada data", 0.0
        return "Naik", 0.08

    change = (recent - previous) / previous
    if change > 0.05:
        return f"Naik ({change * 100:+.1f}%)", change
    if change < -0.05:
        return f"Turun ({change * 100:+.1f}%)", change
    return "Stabil", change


def generate_forecast(
    db: Session, unit_id: int, owner_id: int, horizon: int = 7
) -> Optional[dict]:
    unit = _unit_for_owner(db, unit_id, owner_id)
    if not unit:
        return None

    horizon = 7 if horizon not in (7, 30) else horizon
    lookback = 90
    rows = db.execute(
        text(
            """
            SELECT tanggal::date AS tanggal, SUM(total)::float AS total
            FROM transactions
            WHERE unit_id = :unit_id
              AND status = 'selesai'
              AND tanggal >= CURRENT_DATE - INTERVAL '90 days'
            GROUP BY 1
            ORDER BY 1
            """
        ),
        {"unit_id": unit_id},
    ).mappings().all()

    actual = {row["tanggal"]: float(row["total"] or 0) for row in rows}
    series = _daily_series(actual, lookback)
    daily_values = [value for _, value in series]

    factors = _weekday_factors(series)
    trend_label, trend_change = _trend_label(series)
    baseline = _ewma(daily_values[-28:]) if daily_values else 0.0
    spread = pstdev(daily_values[-28:]) * 1.96 if len(daily_values) >= 2 else 0.0

    proyeksi = []
    today = date.today()
    for offset in range(1, horizon + 1):
        target = today + timedelta(days=offset)
        adjustment = 1 + max(-0.15, min(0.15, trend_change)) * (offset / horizon)
        prediction = max(0.0, baseline * factors[target.weekday()] * adjustment)
        proyeksi.append(
            {
                "tanggal": target,
                "prediksi_penjualan": round(prediction, 2),
                "batas_bawah": round(max(0.0, prediction - spread), 2),
                "batas_atas": round(prediction + spread, 2),
            }
        )

    if baseline <= 0:
        recommendation = (
            "Belum ada transaksi selesai dalam 90 hari terakhir. Catat penjualan "
            "terlebih dahulu agar model dapat menghitung proyeksi."
        )
    elif trend_change < -0.05:
        recommendation = (
            "Tren penjualan menurun. Tahan pembelian stok berlebih, fokus pada "
            "promosi dan pemantauan produk lambat laku."
        )
    elif trend_change > 0.05:
        recommendation = (
            "Tren penjualan meningkat. Tambahkan stok produk terlaris 15-25% dan "
            "pastikan kapasitas kasir mencukupi pada akhir pekan."
        )
    else:
        recommendation = (
            "Penjualan relatif stabil. Pertahankan stok pada level saat ini dan "
            "lakukan restok berkala untuk produk dengan perputaran tinggi."
        )

    return {
        "unit_id": unit_id,
        "nama_unit": unit["nama"],
        "horizon_hari": horizon,
        "tren": trend_label,
        "rekomendasi_stok": recommendation,
        "proyeksi": proyeksi,
    }


def generate_product_forecast(
    db: Session, unit_id: int, owner_id: int, horizon: int = 7
) -> Optional[dict]:
    unit = _unit_for_owner(db, unit_id, owner_id)
    if not unit:
        return None

    horizon = 7 if horizon not in (7, 30) else horizon
    rows = db.execute(
        text(
            """
            SELECT ti.product_id,
                   p.nama AS nama_produk,
                   t.tanggal::date AS tanggal,
                   SUM(ti.qty)::float AS qty
            FROM transaction_items ti
            JOIN transactions t ON t.id = ti.trx_id
            JOIN products p ON p.id = ti.product_id
            WHERE t.unit_id = :unit_id
              AND t.status = 'selesai'
              AND t.tanggal >= CURRENT_DATE - INTERVAL '90 days'
              AND ti.product_id IS NOT NULL
            GROUP BY ti.product_id, p.nama, t.tanggal::date
            ORDER BY ti.product_id, t.tanggal::date
            """
        ),
        {"unit_id": unit_id},
    ).mappings().all()

    grouped: dict[int, dict] = {}
    for row in rows:
        item = grouped.setdefault(
            row["product_id"],
            {"nama_produk": row["nama_produk"], "harian": defaultdict(float)},
        )
        item["harian"][row["tanggal"]] += float(row["qty"] or 0)

    stocks = db.execute(
        text(
            "SELECT product_id, qty, min_stock FROM inventories WHERE unit_id = :unit_id"
        ),
        {"unit_id": unit_id},
    ).mappings().all()
    stock_map = {row["product_id"]: int(row["qty"] or 0) for row in stocks}
    min_stock_map = {row["product_id"]: int(row["min_stock"] or 0) for row in stocks}

    items = []
    today = date.today()
    for product_id, data in grouped.items():
        series = _daily_series(data["harian"], 60)
        daily_values = [value for _, value in series]
        baseline = _ewma(daily_values[-28:]) if daily_values else 0.0
        factors = _weekday_factors(series)

        projections = []
        for offset in range(1, horizon + 1):
            target = today + timedelta(days=offset)
            qty = max(0.0, baseline * factors[target.weekday()])
            projections.append(
                {
                    "tanggal": target,
                    "prediksi_qty": round(qty, 2),
                }
            )

        total_prediction = sum(p["prediksi_qty"] for p in projections)
        stock = stock_map.get(product_id, 0)
        minimum = min_stock_map.get(product_id, 0)

        if stock <= minimum or stock < total_prediction * 0.5:
            status = "RISIKO_KEHABISAN"
        elif total_prediction > 0 and stock > total_prediction * 2.5:
            status = "RISIKO_KELEBIHAN"
        else:
            status = "NORMAL"

        for projection in projections:
            projection["status_risiko"] = status

        items.append(
            {
                "product_id": product_id,
                "nama_produk": data["nama_produk"],
                "stok_saat_ini": stock,
                "total_prediksi": round(total_prediction, 2),
                "status_risiko": status,
                "proyeksi": projections,
            }
        )

    items.sort(key=lambda item: item["total_prediksi"], reverse=True)

    return {
        "unit_id": unit_id,
        "nama_unit": unit["nama"],
        "horizon_hari": horizon,
        "items": items[:20],
    }


def generate_reallocation(db: Session, owner_id: int) -> list[dict]:
    rows = db.execute(
        text(
            """
            SELECT i.product_id,
                   p.nama AS nama_produk,
                   p.harga_beli::float AS harga_beli,
                   i.unit_id,
                   b.nama AS nama_unit,
                   i.qty,
                   i.min_stock,
                   COALESCE(s.qty_30d, 0)::float AS qty_30d
            FROM inventories i
            JOIN products p ON p.id = i.product_id
            JOIN business_units b ON b.id = i.unit_id
            LEFT JOIN (
                SELECT ti.product_id, t.unit_id, SUM(ti.qty)::float AS qty_30d
                FROM transaction_items ti
                JOIN transactions t ON t.id = ti.trx_id
                WHERE t.status = 'selesai'
                  AND t.tanggal >= CURRENT_DATE - INTERVAL '30 days'
                  AND ti.product_id IS NOT NULL
                GROUP BY ti.product_id, t.unit_id
            ) s ON s.product_id = i.product_id AND s.unit_id = i.unit_id
            WHERE b.owner_id = :owner_id
            """
        ),
        {"owner_id": owner_id},
    ).mappings().all()

    products: dict[int, list[dict]] = defaultdict(list)
    for row in rows:
        qty = int(row["qty"] or 0)
        sold = float(row["qty_30d"] or 0)
        avg_daily = sold / 30.0
        days_cover = (qty / avg_daily) if avg_daily > 0 else 0.0
        products[row["product_id"]].append(
            {
                "unit_id": row["unit_id"],
                "nama_unit": row["nama_unit"],
                "nama_produk": row["nama_produk"],
                "harga_beli": float(row["harga_beli"] or 0),
                "qty": qty,
                "min_stock": int(row["min_stock"] or 0),
                "avg_daily": avg_daily,
                "days_cover": days_cover,
                "sold": sold,
            }
        )

    recommendations = []
    next_id = 1
    for product_id, units in products.items():
        surplus_units = [
            u for u in units if u["avg_daily"] > 0 and u["days_cover"] > 30
        ]
        deficit_units = [
            u for u in units if u["avg_daily"] > 0 and u["days_cover"] < 7
        ]
        surplus_units.sort(key=lambda u: u["days_cover"], reverse=True)
        deficit_units.sort(key=lambda u: u["days_cover"])

        for surplus in surplus_units:
            if not deficit_units:
                break
            deficit = deficit_units[0]
            if surplus["unit_id"] == deficit["unit_id"]:
                continue

            surplus_qty = max(
                0,
                int((surplus["days_cover"] - 30) * surplus["avg_daily"]),
            )
            deficit_qty = max(
                0,
                int((7 - deficit["days_cover"]) * deficit["avg_daily"]),
            )
            movable = min(surplus_qty, deficit_qty)
            movable = min(movable, max(0, surplus["qty"] - surplus["min_stock"]))
            if movable < 1:
                continue

            recommendations.append(
                {
                    "id": next_id,
                    "product_id": product_id,
                    "nama_produk": surplus["nama_produk"],
                    "unit_sumber_id": surplus["unit_id"],
                    "unit_sumber": surplus["nama_unit"],
                    "unit_tujuan_id": deficit["unit_id"],
                    "unit_tujuan": deficit["nama_unit"],
                    "jumlah_pindah": movable,
                    "alasan_ai": (
                        f"Stok di {surplus['nama_unit']} cukup untuk "
                        f"{surplus['days_cover']:.0f} hari, sedangkan "
                        f"{deficit['nama_unit']} hanya {deficit['days_cover']:.1f} hari. "
                        f"Pindahkan {movable} unit untuk mencegah stockout."
                    ),
                    "estimasi_hemat_biaya": round(movable * surplus["harga_beli"], 2),
                }
            )
            next_id += 1

            deficit["qty"] += movable
            deficit["days_cover"] = (
                deficit["qty"] / deficit["avg_daily"]
                if deficit["avg_daily"] > 0
                else 0.0
            )
            if deficit["days_cover"] >= 7:
                deficit_units.pop(0)

    recommendations.sort(key=lambda item: item["estimasi_hemat_biaya"], reverse=True)
    return recommendations
