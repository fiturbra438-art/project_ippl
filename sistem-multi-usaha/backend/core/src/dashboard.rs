use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use rust_decimal::prelude::ToPrimitive;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::auth::{accessible_unit_ids, ensure_unit_access};
use crate::models::{Claims, PaketLangganan};
use crate::schemas::ApiResponse;
use crate::state::AppState;

#[derive(Debug, Serialize)]
pub struct UnitPerformaItem {
    pub id: i64,
    pub nama: String,
    pub jenis_usaha: String,
    pub kategori_portofolio: String,
    pub pendapatan: f64,
    pub pengeluaran: f64,
    pub laba_bersih: f64,
    pub margin_persen: f64,
}

#[derive(Debug, Serialize)]
pub struct KonsolidasiDashboardResponse {
    pub total_unit_usaha: usize,
    pub total_pendapatan: f64,
    pub total_pengeluaran: f64,
    pub laba_bersih_konsolidasi: f64,
    pub margin_konsolidasi_persen: f64,
    pub total_produk_kritis: usize,
    pub sisa_kuota_ai: i32,
    pub paket_langganan: PaketLangganan,
    pub unit_performa: Vec<UnitPerformaItem>,
}

#[derive(Debug, Deserialize)]
pub struct LaporanQuery {
    pub unit_id: Option<i64>,
    pub tanggal_mulai: Option<chrono::NaiveDate>,
    pub tanggal_akhir: Option<chrono::NaiveDate>,
    pub metode_pembayaran: Option<String>,
    pub status_transaksi: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct KategoriSummary {
    pub kategori: String,
    pub total: f64,
}

#[derive(Debug, Serialize)]
pub struct LaporanKeuanganResponse {
    pub total_pemasukan: f64,
    pub total_pengeluaran: f64,
    pub arus_kas_bersih: f64,
    pub omzet_kotor: f64,
    pub diskon: f64,
    pub refund: f64,
    pub omzet_bersih: f64,
    pub hpp: f64,
    pub laba_kotor: f64,
    pub rincian_pemasukan_per_kategori: Vec<KategoriSummary>,
    pub rincian_pengeluaran_per_kategori: Vec<KategoriSummary>,
}

// 1. RINGKASAN DASHBOARD OWNER KONSOLIDASI (Strict Auth & Real-Time dari PostgreSQL)
pub async fn get_dashboard_summary(
    State(state): State<Arc<AppState>>,
    claims: Claims,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;
    let is_owner_or_auditor = claims.role == "owner" || claims.role == "auditor";

    // Ambil data paket & kuota dari tabel PostgreSQL `users`
    let user_row = sqlx::query_as::<_, (Option<String>, Option<i32>)>(
        "SELECT tier, sisa_kuota_ai FROM users WHERE id = $1",
    )
    .bind(owner_id as i32)
    .fetch_optional(&state.db)
    .await
    .unwrap_or(None);

    let (tier_str, sisa_ai) = user_row.unwrap_or((Some("pro".to_string()), Some(250)));
    let paket = match tier_str.as_deref() {
        Some("enterprise") => PaketLangganan::Enterprise,
        Some("free") => PaketLangganan::Free,
        _ => PaketLangganan::Pro,
    };

    // Ambil unit usaha: Jika karyawan/manajer, batasi hanya unit yang diizinkan untuknya
    let usaha_rows = if is_owner_or_auditor {
        sqlx::query_as::<_, (i32, String, String, Option<String>)>(
            "SELECT id, nama, jenis_usaha, kategori_portofolio 
             FROM business_units 
             WHERE owner_id = $1",
        )
        .bind(owner_id as i32)
        .fetch_all(&state.db)
        .await
        .unwrap_or_default()
    } else {
        sqlx::query_as::<_, (i32, String, String, Option<String>)>(
            "SELECT u.id, u.nama, u.jenis_usaha, u.kategori_portofolio 
             FROM business_units u
             JOIN user_units uu ON uu.unit_id = u.id
             WHERE u.owner_id = $1 AND uu.user_id = $2",
        )
        .bind(owner_id as i32)
        .bind(claims.user_id as i32)
        .fetch_all(&state.db)
        .await
        .unwrap_or_default()
    };

    let total_unit = usaha_rows.len();
    let mut unit_performa: Vec<UnitPerformaItem> = Vec::new();
    let mut total_pendapatan = 0.0;
    let mut total_pengeluaran = 0.0;

    for u in usaha_rows {
        // Hitung pendapatan riil dari transactions tabel PostgreSQL
        let p_decimal: Option<rust_decimal::Decimal> = sqlx::query_scalar(
            "SELECT COALESCE(SUM(total), 0) FROM transactions WHERE unit_id = $1 AND status = 'selesai'"
        )
        .bind(u.0)
        .fetch_optional(&state.db)
        .await
        .unwrap_or(None);
        let pendapatan_pos = p_decimal.and_then(|d| d.to_f64()).unwrap_or(0.0);

        // Pendapatan & pengeluaran manual dari tabel cash_flows
        let cash_masuk: Option<rust_decimal::Decimal> = sqlx::query_scalar(
            "SELECT COALESCE(SUM(jumlah), 0) FROM cash_flows WHERE unit_id = $1 AND jenis = 'masuk'",
        )
        .bind(u.0)
        .fetch_optional(&state.db)
        .await
        .unwrap_or(None);
        let cash_keluar: Option<rust_decimal::Decimal> = sqlx::query_scalar(
            "SELECT COALESCE(SUM(jumlah), 0) FROM cash_flows WHERE unit_id = $1 AND jenis = 'keluar'",
        )
        .bind(u.0)
        .fetch_optional(&state.db)
        .await
        .unwrap_or(None);

        let pendapatan = pendapatan_pos + cash_masuk.and_then(|d| d.to_f64()).unwrap_or(0.0);
        let pengeluaran = cash_keluar.and_then(|d| d.to_f64()).unwrap_or(0.0);
        let laba = pendapatan - pengeluaran;
        let margin = if pendapatan > 0.0 {
            (laba / pendapatan) * 100.0
        } else {
            0.0
        };

        total_pendapatan += pendapatan;
        total_pengeluaran += pengeluaran;

        unit_performa.push(UnitPerformaItem {
            id: u.0 as i64,
            nama: u.1,
            jenis_usaha: u.2,
            kategori_portofolio: u.3.unwrap_or_else(|| "Star".to_string()),
            pendapatan,
            pengeluaran,
            laba_bersih: laba,
            margin_persen: (margin * 10.0).round() / 10.0,
        });
    }

    let laba_bersih = total_pendapatan - total_pengeluaran;
    let margin_persen = if total_pendapatan > 0.0 {
        (laba_bersih / total_pendapatan) * 100.0
    } else {
        0.0
    };

    // Hitung produk kritis dari view PostgreSQL (disesuaikan dengan peran pengguna)
    let total_produk_kritis: i64 = if is_owner_or_auditor {
        sqlx::query_scalar(
            "SELECT COUNT(*) FROM view_produk_stok_kritis WHERE unit_id IN (SELECT id FROM business_units WHERE owner_id = $1)",
        )
        .bind(owner_id as i32)
        .fetch_one(&state.db)
        .await
        .unwrap_or(0)
    } else {
        sqlx::query_scalar(
            "SELECT COUNT(*) FROM view_produk_stok_kritis WHERE unit_id IN (SELECT unit_id FROM user_units WHERE user_id = $1)",
        )
        .bind(claims.user_id as i32)
        .fetch_one(&state.db)
        .await
        .unwrap_or(0)
    };

    let res = KonsolidasiDashboardResponse {
        total_unit_usaha: total_unit,
        total_pendapatan,
        total_pengeluaran,
        laba_bersih_konsolidasi: laba_bersih,
        margin_konsolidasi_persen: (margin_persen * 10.0).round() / 10.0,
        total_produk_kritis: total_produk_kritis as usize,
        sisa_kuota_ai: sisa_ai.unwrap_or(250),
        paket_langganan: paket,
        unit_performa,
    };

    (
        StatusCode::OK,
        Json(ApiResponse::<KonsolidasiDashboardResponse> {
            status: "success".to_string(),
            message: "Ringkasan konsolidasi multi-usaha berhasil dihitung dari PostgreSQL."
                .to_string(),
            data: Some(res),
        }),
    )
        .into_response()
}

// 2. LAPORAN KEUANGAN & ARUS KAS (Strict Auth dari PostgreSQL)
pub async fn get_laporan_keuangan(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Query(query): Query<LaporanQuery>,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;

    if let Some(uid) = query.unit_id {
        if let Err(err) = ensure_unit_access(&state, &claims, uid).await {
            return err;
        }
    }
    if query
        .tanggal_mulai
        .zip(query.tanggal_akhir)
        .is_some_and(|(start, end)| start > end)
    {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<LaporanKeuanganResponse> {
                status: "error".to_string(),
                message: "Tanggal mulai tidak boleh setelah tanggal akhir.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }
    let scoped_ids =
        if query.unit_id.is_none() && !["owner", "auditor"].contains(&claims.role.as_str()) {
            match accessible_unit_ids(&state, &claims).await {
                Ok(ids) => Some(ids),
                Err(error) => return error,
            }
        } else {
            None
        };
    let selected_status = query.status_transaksi.as_deref().or(Some("selesai"));
    let rows = sqlx::query_as::<
        _,
        (
            rust_decimal::Decimal,
            String,
            rust_decimal::Decimal,
            rust_decimal::Decimal,
        ),
    >(
        "SELECT t.total, t.metode_bayar,
                COALESCE((SELECT SUM(ti.harga_satuan * ti.qty)
                          FROM transaction_items ti WHERE ti.trx_id = t.id), t.total),
                COALESCE((SELECT SUM(p.harga_beli * ti.qty)
                          FROM transaction_items ti
                          JOIN products p ON p.id = ti.product_id
                          WHERE ti.trx_id = t.id AND ti.item_type = 'barang'), 0)
         FROM transactions t
         JOIN business_units u ON u.id = t.unit_id
         WHERE u.owner_id = $1
           AND ($2::INT IS NULL OR t.unit_id = $2)
           AND ($3::DATE IS NULL OR t.tanggal >= $3::DATE)
           AND ($4::DATE IS NULL OR t.tanggal < ($4::DATE + INTERVAL '1 day'))
           AND ($5::TEXT IS NULL OR t.metode_bayar = $5)
           AND ($6::TEXT IS NULL OR t.status = $6)
           AND ($7::INT[] IS NULL OR t.unit_id = ANY($7))
         ORDER BY t.tanggal, t.id",
    )
    .bind(owner_id as i32)
    .bind(query.unit_id.map(|unit_id| unit_id as i32))
    .bind(query.tanggal_mulai)
    .bind(query.tanggal_akhir)
    .bind(query.metode_pembayaran.as_deref())
    .bind(selected_status)
    .bind(scoped_ids.as_deref())
    .fetch_all(&state.db)
    .await;
    let rows = match rows {
        Ok(rows) => rows,
        Err(error) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<LaporanKeuanganResponse> {
                    status: "error".to_string(),
                    message: format!("Gagal mengambil transaksi laporan: {error}"),
                    data: None,
                }),
            )
                .into_response()
        }
    };
    let cash_rows = sqlx::query_as::<_, (String, String, rust_decimal::Decimal)>(
        "SELECT c.jenis, c.kategori, c.jumlah
         FROM cash_flows c
         JOIN business_units u ON u.id = c.unit_id
         WHERE u.owner_id = $1
           AND ($2::INT IS NULL OR c.unit_id = $2)
           AND ($3::DATE IS NULL OR c.tanggal >= $3::DATE)
           AND ($4::DATE IS NULL OR c.tanggal <= $4::DATE)
           AND ($5::INT[] IS NULL OR c.unit_id = ANY($5))
           AND c.kategori <> 'Penjualan POS'",
    )
    .bind(owner_id as i32)
    .bind(query.unit_id.map(|unit_id| unit_id as i32))
    .bind(query.tanggal_mulai)
    .bind(query.tanggal_akhir)
    .bind(scoped_ids.as_deref())
    .fetch_all(&state.db)
    .await;
    let cash_rows = match cash_rows {
        Ok(rows) => rows,
        Err(error) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<LaporanKeuanganResponse> {
                    status: "error".to_string(),
                    message: format!("Gagal mengambil arus kas laporan: {error}"),
                    data: None,
                }),
            )
                .into_response()
        }
    };
    let mut total_pengeluaran = 0.0;
    use std::collections::HashMap;
    let mut map_pemasukan: HashMap<String, f64> = HashMap::new();
    let mut map_pengeluaran: HashMap<String, f64> = HashMap::new();
    let mut omzet_kotor = 0.0;
    let mut omzet_bersih = 0.0;
    let mut hpp = 0.0;

    for (total_dec, metode, gross_dec, hpp_dec) in rows {
        let jml = total_dec.to_f64().unwrap_or_default();
        omzet_bersih += jml;
        omzet_kotor += gross_dec.to_f64().unwrap_or_default();
        hpp += hpp_dec.to_f64().unwrap_or_default();
        *map_pemasukan
            .entry(format!("Penjualan ({})", metode))
            .or_insert(0.0) += jml;
    }
    let mut total_pemasukan = omzet_bersih;

    for (jenis, kategori, jumlah) in cash_rows {
        let jml = jumlah.to_f64().unwrap_or(0.0);
        if jenis.eq_ignore_ascii_case("masuk") {
            total_pemasukan += jml;
            *map_pemasukan.entry(kategori).or_insert(0.0) += jml;
        } else {
            total_pengeluaran += jml;
            *map_pengeluaran.entry(kategori).or_insert(0.0) += jml;
        }
    }

    let rincian_pemasukan_per_kategori: Vec<KategoriSummary> = map_pemasukan
        .into_iter()
        .map(|(kategori, total)| KategoriSummary { kategori, total })
        .collect();
    let rincian_pengeluaran_per_kategori: Vec<KategoriSummary> = map_pengeluaran
        .into_iter()
        .map(|(kategori, total)| KategoriSummary { kategori, total })
        .collect();

    let res = LaporanKeuanganResponse {
        total_pemasukan,
        total_pengeluaran,
        arus_kas_bersih: total_pemasukan - total_pengeluaran,
        omzet_kotor,
        diskon: (omzet_kotor - omzet_bersih).max(0.0),
        refund: 0.0,
        omzet_bersih,
        hpp,
        laba_kotor: omzet_bersih - hpp,
        rincian_pemasukan_per_kategori,
        rincian_pengeluaran_per_kategori,
    };

    (
        StatusCode::OK,
        Json(ApiResponse::<LaporanKeuanganResponse> {
            status: "success".to_string(),
            message: "Laporan keuangan berhasil dihitung dari PostgreSQL.".to_string(),
            data: Some(res),
        }),
    )
        .into_response()
}
