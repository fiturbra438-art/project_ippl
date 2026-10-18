use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use serde::Serialize;
use std::sync::Arc;

use crate::auth::extract_claims;
use crate::schemas::{ApiResponse, ChatAiRequest, ChatAiResponse};
use crate::state::AppState;

#[derive(Debug, Serialize)]
pub struct ForecastPoint {
    pub tanggal: String,
    pub prediksi_penjualan: f64,
    pub batas_bawah: f64,
    pub batas_atas: f64,
}

#[derive(Debug, Serialize)]
pub struct ForecastResponse {
    pub unit_id: i64,
    pub nama_unit: String,
    pub tren: String, // Naik, Stabil, Turun
    pub rekomendasi_stok: String,
    pub proyeksi_7_hari: Vec<ForecastPoint>,
}

#[derive(Debug, Serialize)]
pub struct AnomaliItem {
    pub id: i64,
    pub unit_id: i64,
    pub nama_unit: String,
    pub tingkat_bahaya: String, // Rendah, Sedang, Kritis
    pub judul: String,
    pub deskripsi: String,
    pub rekomendasi: String,
}

// 1. CHATBOT BI ASSISTANT (Memeriksa dan memotong kuota AI owner)
pub async fn chat_ai(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<ChatAiRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    // Cek kuota AI Owner
    let mut owners = state.owners.write().await;
    let owner = match owners.iter_mut().find(|o| o.id == owner_id) {
        Some(o) => {
            if o.sisa_kuota_ai <= 0 {
                return (
                    StatusCode::FORBIDDEN,
                    Json(ApiResponse::<ChatAiResponse> {
                        status: "error".to_string(),
                        message: "Kuota pertanyaan AI Anda telah habis. Silakan upgrade paket ke Pro atau Enterprise untuk mendapatkan kuota tambahan.".to_string(),
                        data: None,
                    }),
                );
            }
            o.sisa_kuota_ai -= 1;
            o.clone()
        }
        None => {
            return (
                StatusCode::NOT_FOUND,
                Json(ApiResponse::<ChatAiResponse> {
                    status: "error".to_string(),
                    message: "Owner tidak ditemukan.".to_string(),
                    data: None,
                }),
            );
        }
    };
    drop(owners);

    // Ambil data kontekstual bisnis
    let usahas = state.usahas.read().await;
    let total_usaha = usahas.iter().filter(|u| u.owner_id == owner_id).count();
    let total_omzet: f64 = usahas.iter().filter(|u| u.owner_id == owner_id).map(|u| u.pendapatan_bulan_ini).sum();
    let star_units: Vec<String> = usahas
        .iter()
        .filter(|u| u.owner_id == owner_id && u.kategori_portofolio == "Star")
        .map(|u| u.nama.clone())
        .collect();
    drop(usahas);

    let produks = state.produks.read().await;
    let produk_kritis: Vec<String> = produks
        .iter()
        .filter(|p| p.owner_id == owner_id && p.stok <= p.min_stok)
        .map(|p| format!("{} (sisa {})", p.nama, p.stok))
        .collect();
    drop(produks);

    let query_lower = payload.pesan.to_lowercase();
    let balasan = if query_lower.contains("omzet") || query_lower.contains("pendapatan") {
        format!(
            "Total omzet konsolidasi bulan ini di seluruh {} unit usaha Anda mencapai Rp {:.0}. Unit unggulan 'Star' saat ini adalah: {}.",
            total_usaha, total_omzet, star_units.join(", ")
        )
    } else if query_lower.contains("stok") || query_lower.contains("gudang") || query_lower.contains("kritis") {
        if produk_kritis.is_empty() {
            "Semua stok produk saat ini dalam kondisi aman di atas batas minimum.".to_string()
        } else {
            format!(
                "Peringatan Stok Kritis! Terdapat {} barang yang berada di bawah batas minimum: {}. Disarankan segera mengajukan permintaan stok atau transfer gudang.",
                produk_kritis.len(), produk_kritis.join(", ")
            )
        }
    } else if query_lower.contains("saran") || query_lower.contains("rekomendasi") || query_lower.contains("strategi") {
        format!(
            "Berdasarkan matriks BCG portofolio Anda, tingkatkan alokasi modal kerja pada unit kategori 'Star' ({}) untuk akselerasi pertumbuhan, serta lakukan efisiensi pengeluaran operasional pada unit kategori 'Question Mark'.",
            star_units.join(", ")
        )
    } else {
        format!(
            "Halo Bpk/Ibu Owner! Asisten AI BI siap membantu memantau {} unit usaha Anda di {}. Anda dapat menanyakan ringkasan omzet, analisis stok menipis, evaluasi margin laba, atau proyeksi penjualan pekan depan.",
            total_usaha, owner.nama_bisnis_induk
        )
    };

    (
        StatusCode::OK,
        Json(ApiResponse::<ChatAiResponse> {
            status: "success".to_string(),
            message: "Berhasil dijawab oleh Sistem AI BI Core.".to_string(),
            data: Some(ChatAiResponse {
                balasan,
                sumber: "Hybrid AI Intelligence Engine (Rust Core + Python Data Model)".to_string(),
                sisa_kuota_ai: owner.sisa_kuota_ai,
            }),
        }),
    )
}

// 2. FORECASTING DEMAND PENJUALAN
pub async fn get_forecast(
    State(state): State<Arc<AppState>>,
    Path(unit_id): Path<i64>,
) -> impl IntoResponse {
    let usahas = state.usahas.read().await;
    let nama_unit = match usahas.iter().find(|u| u.id == unit_id) {
        Some(u) => u.nama.clone(),
        None => "Unit Usaha".to_string(),
    };
    drop(usahas);

    let proyeksi = vec![
        ForecastPoint {
            tanggal: "2026-10-18".to_string(),
            prediksi_penjualan: 1850000.0,
            batas_bawah: 1600000.0,
            batas_atas: 2100000.0,
        },
        ForecastPoint {
            tanggal: "2026-10-19".to_string(),
            prediksi_penjualan: 1920000.0,
            batas_bawah: 1700000.0,
            batas_atas: 2200000.0,
        },
        ForecastPoint {
            tanggal: "2026-10-20".to_string(),
            prediksi_penjualan: 2450000.0,
            batas_bawah: 2100000.0,
            batas_atas: 2800000.0,
        },
        ForecastPoint {
            tanggal: "2026-10-21".to_string(),
            prediksi_penjualan: 2600000.0,
            batas_bawah: 2250000.0,
            batas_atas: 3000000.0,
        },
        ForecastPoint {
            tanggal: "2026-10-22".to_string(),
            prediksi_penjualan: 2100000.0,
            batas_bawah: 1850000.0,
            batas_atas: 2350000.0,
        },
        ForecastPoint {
            tanggal: "2026-10-23".to_string(),
            prediksi_penjualan: 3100000.0,
            batas_bawah: 2700000.0,
            batas_atas: 3500000.0,
        },
        ForecastPoint {
            tanggal: "2026-10-24".to_string(),
            prediksi_penjualan: 3400000.0,
            batas_bawah: 2950000.0,
            batas_atas: 3850000.0,
        },
    ];

    let res = ForecastResponse {
        unit_id,
        nama_unit,
        tren: "Meningkat (+14.8%)".to_string(),
        rekomendasi_stok: "Siapkan penambahan bahan baku sebesar 20% menjelang akhir pekan karena estimasi lonjakan pesanan.".to_string(),
        proyeksi_7_hari: proyeksi,
    };

    (
        StatusCode::OK,
        Json(ApiResponse::<ForecastResponse> {
            status: "success".to_string(),
            message: "Data forecasting tren penjualan berhasil dianalisis.".to_string(),
            data: Some(res),
        }),
    )
}

// 3. DETEKSI ANOMALI BISNIS
pub async fn get_anomali(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    let produks = state.produks.read().await;
    let mut anomalis: Vec<AnomaliItem> = Vec::new();

    // Cek anomali stok kritis
    for p in produks.iter().filter(|p| p.owner_id == owner_id && p.stok <= p.min_stok) {
        anomalis.push(AnomaliItem {
            id: anomalis.len() as i64 + 1,
            unit_id: p.unit_id,
            nama_unit: format!("Unit #{}", p.unit_id),
            tingkat_bahaya: "Kritis".to_string(),
            judul: format!("Stok Menipis: {}", p.nama),
            deskripsi: format!("Sisa stok {} unit, berada di bawah batas aman minimum ({} unit).", p.stok, p.min_stok),
            rekomendasi: "Lakukan restock atau ajukan mutasi dari gudang utama segera.".to_string(),
        });
    }
    drop(produks);

    // Cek anomali margin atau pengeluaran
    let usahas = state.usahas.read().await;
    for u in usahas.iter().filter(|u| u.owner_id == owner_id) {
        if u.pengeluaran_bulan_ini > u.pendapatan_bulan_ini && u.pendapatan_bulan_ini > 0.0 {
            anomalis.push(AnomaliItem {
                id: anomalis.len() as i64 + 1,
                unit_id: u.id,
                nama_unit: u.nama.clone(),
                tingkat_bahaya: "Sedang".to_string(),
                judul: "Pengeluaran Melebihi Pendapatan".to_string(),
                deskripsi: format!(
                    "Pengeluaran bulan ini (Rp {:.0}) melebihi pendapatan (Rp {:.0}). Defisit: Rp {:.0}",
                    u.pengeluaran_bulan_ini, u.pendapatan_bulan_ini, u.pengeluaran_bulan_ini - u.pendapatan_bulan_ini
                ),
                rekomendasi: "Audit pos pengeluaran operasional dan biaya variabel unit ini.".to_string(),
            });
        }
    }
    drop(usahas);

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<AnomaliItem>> {
            status: "success".to_string(),
            message: format!("Deteksi anomali selesai. Ditemukan {} anomali bisnis.", anomalis.len()),
            data: Some(anomalis),
        }),
    )
}
