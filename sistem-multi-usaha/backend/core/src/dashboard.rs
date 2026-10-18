use axum::{
    extract::{Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::auth::extract_claims;
use crate::models::{JenisTransaksi, PaketLangganan};
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
    pub rincian_pemasukan_per_kategori: Vec<KategoriSummary>,
    pub rincian_pengeluaran_per_kategori: Vec<KategoriSummary>,
}

// 1. RINGKASAN DASHBOARD OWNER KONSOLIDASI
pub async fn get_dashboard_summary(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    let owners = state.owners.read().await;
    let (paket, sisa_ai) = match owners.iter().find(|o| o.id == owner_id) {
        Some(o) => (o.paket_langganan.clone(), o.sisa_kuota_ai),
        None => (PaketLangganan::Free, 20),
    };
    drop(owners);

    let usahas = state.usahas.read().await;
    let my_usahas: Vec<_> = usahas.iter().filter(|u| u.owner_id == owner_id).collect();

    let total_unit = my_usahas.len();
    let total_pendapatan: f64 = my_usahas.iter().map(|u| u.pendapatan_bulan_ini).sum();
    let total_pengeluaran: f64 = my_usahas.iter().map(|u| u.pengeluaran_bulan_ini).sum();
    let laba_bersih = total_pendapatan - total_pengeluaran;
    let margin_persen = if total_pendapatan > 0.0 {
        (laba_bersih / total_pendapatan) * 100.0
    } else {
        0.0
    };

    let unit_performa: Vec<UnitPerformaItem> = my_usahas
        .iter()
        .map(|u| {
            let laba = u.pendapatan_bulan_ini - u.pengeluaran_bulan_ini;
            let margin = if u.pendapatan_bulan_ini > 0.0 {
                (laba / u.pendapatan_bulan_ini) * 100.0
            } else {
                0.0
            };
            UnitPerformaItem {
                id: u.id,
                nama: u.nama.clone(),
                jenis_usaha: u.jenis_usaha.clone(),
                kategori_portofolio: u.kategori_portofolio.clone(),
                pendapatan: u.pendapatan_bulan_ini,
                pengeluaran: u.pengeluaran_bulan_ini,
                laba_bersih: laba,
                margin_persen: (margin * 10.0).round() / 10.0,
            }
        })
        .collect();
    drop(usahas);

    let produks = state.produks.read().await;
    let total_produk_kritis = produks
        .iter()
        .filter(|p| p.owner_id == owner_id && p.stok <= p.min_stok)
        .count();
    drop(produks);

    let res = KonsolidasiDashboardResponse {
        total_unit_usaha: total_unit,
        total_pendapatan,
        total_pengeluaran,
        laba_bersih_konsolidasi: laba_bersih,
        margin_konsolidasi_persen: (margin_persen * 10.0).round() / 10.0,
        total_produk_kritis,
        sisa_kuota_ai: sisa_ai,
        paket_langganan: paket,
        unit_performa,
    };

    (
        StatusCode::OK,
        Json(ApiResponse::<KonsolidasiDashboardResponse> {
            status: "success".to_string(),
            message: "Ringkasan konsolidasi multi-usaha berhasil dihitung.".to_string(),
            data: Some(res),
        }),
    )
}

// 2. LAPORAN KEUANGAN & ARUS KAS (Bisa difilter per unit atau konsolidasi)
pub async fn get_laporan_keuangan(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Query(query): Query<LaporanQuery>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    let transaksis = state.transaksis.read().await;
    let filtered_trxs: Vec<_> = transaksis
        .iter()
        .filter(|t| {
            if t.owner_id != owner_id {
                return false;
            }
            if let Some(uid) = query.unit_id {
                if uid > 0 && t.unit_id != uid {
                    return false;
                }
            }
            true
        })
        .collect();

    let mut total_pemasukan = 0.0;
    let mut total_pengeluaran = 0.0;
    use std::collections::HashMap;
    let mut map_pemasukan: HashMap<String, f64> = HashMap::new();
    let mut map_pengeluaran: HashMap<String, f64> = HashMap::new();

    for t in filtered_trxs {
        match t.jenis {
            JenisTransaksi::Pemasukan => {
                total_pemasukan += t.jumlah;
                *map_pemasukan.entry(t.kategori.clone()).or_insert(0.0) += t.jumlah;
            }
            JenisTransaksi::Pengeluaran => {
                total_pengeluaran += t.jumlah;
                *map_pengeluaran.entry(t.kategori.clone()).or_insert(0.0) += t.jumlah;
            }
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
        rincian_pemasukan_per_kategori,
        rincian_pengeluaran_per_kategori,
    };

    (
        StatusCode::OK,
        Json(ApiResponse::<LaporanKeuanganResponse> {
            status: "success".to_string(),
            message: "Laporan keuangan berhasil dihitung.".to_string(),
            data: Some(res),
        }),
    )
}
