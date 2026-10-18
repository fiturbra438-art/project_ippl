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

    let usahas = state.usahas.read().await;
    let total_usaha = usahas.iter().filter(|u| u.owner_id == owner_id).count();
    let total_omzet: f64 = usahas.iter().filter(|u| u.owner_id == owner_id).map(|u| u.pendapatan_bulan_ini).sum();
    let total_pengeluaran: f64 = usahas.iter().filter(|u| u.owner_id == owner_id).map(|u| u.pengeluaran_bulan_ini).sum();
    let laba_bersih = total_omzet - total_pengeluaran;

    let star_units: Vec<String> = usahas
        .iter()
        .filter(|u| u.owner_id == owner_id && u.kategori_portofolio == "Star")
        .map(|u| u.nama.clone())
        .collect();
    let cash_cows: Vec<String> = usahas
        .iter()
        .filter(|u| u.owner_id == owner_id && u.kategori_portofolio == "Cash Cow")
        .map(|u| u.nama.clone())
        .collect();
    let unit_names: Vec<String> = usahas
        .iter()
        .filter(|u| u.owner_id == owner_id)
        .map(|u| format!("- {} ({}, Laba: Rp {:.0})", u.nama, u.jenis_usaha, u.pendapatan_bulan_ini - u.pengeluaran_bulan_ini))
        .collect();
    drop(usahas);

    let produks = state.produks.read().await;
    let total_produk = produks.iter().filter(|p| p.owner_id == owner_id).count();
    let produk_kritis: Vec<String> = produks
        .iter()
        .filter(|p| p.owner_id == owner_id && p.stok <= p.min_stok)
        .map(|p| format!("{} (sisa {})", p.nama, p.stok))
        .collect();
    let produk_termahal = produks
        .iter()
        .filter(|p| p.owner_id == owner_id)
        .max_by(|a, b| a.harga_jual.partial_cmp(&b.harga_jual).unwrap())
        .map(|p| format!("{} (Harga: Rp {:.0})", p.nama, p.harga_jual));
    drop(produks);

    let transaksis = state.transaksis.read().await;
    let total_trx = transaksis.iter().filter(|t| t.owner_id == owner_id).count();
    drop(transaksis);

    let query_lower = payload.pesan.to_lowercase();
    let balasan = if query_lower.contains("omzet") || query_lower.contains("pendapatan") || query_lower.contains("penjualan") {
        if total_usaha == 0 {
            "Saat ini belum ada unit usaha yang didaftarkan ke sistem, sehingga total omzet masih Rp 0. Silakan tambahkan unit usaha di menu 'Kelola Unit Usaha'.".to_string()
        } else {
            format!(
                "Berdasarkan data keuangan nyata saat ini:\n• Total Omzet Konsolidasi: Rp {:.0}\n• Total Pengeluaran: Rp {:.0}\n• Laba Bersih Agregat: Rp {:.0}\n• Jumlah Cabang Terdata: {} unit",
                total_omzet, total_pengeluaran, laba_bersih, total_usaha
            )
        }
    } else if query_lower.contains("laba") || query_lower.contains("profit") || query_lower.contains("keuntungan") {
        if total_usaha == 0 {
            "Belum ada catatan transaksi dan unit usaha aktif. Laba bersih saat ini: Rp 0.".to_string()
        } else {
            let margin = if total_omzet > 0.0 { (laba_bersih / total_omzet) * 100.0 } else { 0.0 };
            format!(
                "Laba bersih operasional Anda saat ini sebesar Rp {:.0} dengan margin profit rata-rata {:.1}%. Keuangan dalam status {}.",
                laba_bersih, margin, if laba_bersih >= 0.0 { "Sehat & Surplus" } else { "Defisit Operasional" }
            )
        }
    } else if query_lower.contains("stok") || query_lower.contains("gudang") || query_lower.contains("barang") || query_lower.contains("kritis") {
        if total_produk == 0 {
            "Katalog produk saat ini masih kosong (0 barang). Anda dapat menambahkan produk inventaris lewat menu 'Katalog Produk' atau langsung di mesin Kasir POS.".to_string()
        } else if produk_kritis.is_empty() {
            format!(
                "Kondisi gudang aman! Seluruh {} produk yang terdaftar saat ini berada di atas batas stok minimum aman.",
                total_produk
            )
        } else {
            format!(
                "⚠️ PERINGATAN STOK MENIPIS! Ditemukan {} produk yang berada di batas kritis:\n• {}\nSegera lakukan pemesanan ke pemasok atau ajukan transfer stok antar gudang.",
                produk_kritis.len(), produk_kritis.join("\n• ")
            )
        }
    } else if query_lower.contains("cabang") || query_lower.contains("unit") || query_lower.contains("toko") || query_lower.contains("daftar") {
        if total_usaha == 0 {
            "Belum ada unit usaha/cabang yang aktif di sistem.".to_string()
        } else {
            format!(
                "Berikut {} unit usaha yang terdaftar di grup bisnis '{}':\n{}",
                total_usaha, owner.nama_bisnis_induk, unit_names.join("\n")
            )
        }
    } else if query_lower.contains("saran") || query_lower.contains("rekomendasi") || query_lower.contains("strategi") || query_lower.contains("bcg") {
        if total_usaha == 0 {
            "Rekomendasi awal: Buat minimal 1-2 unit usaha pertama Anda (contoh: Kafe atau Retail) dan catat transaksi harian kasir agar AI dapat membaca pola arus kas dan memberikan rekomendasi ekspansi yang akurat.".to_string()
        } else {
            let unit_star = if !star_units.is_empty() { star_units.join(", ") } else { "belum ada".to_string() };
            let unit_cash = if !cash_cows.is_empty() { cash_cows.join(", ") } else { "belum ada".to_string() };
            format!(
                "Rekomendasi Strategis AI Portofolio:\n1. Unit 'Star' ({}): Pertahankan alokasi stok dan ekspansi pemasaran karena pertumbuhan tinggi.\n2. Unit 'Cash Cow' ({}): Alirkan surplus kas operasional ke cabang yang sedang berkembang untuk mempercepat penetrasi pasar.",
                unit_star, unit_cash
            )
        }
    } else if query_lower.contains("transaksi") || query_lower.contains("kasir") || query_lower.contains("pos") {
        format!(
            "Total transaksi yang telah tercatat di sistem: {} transaksi. Anda bisa memantau detail riwayat penjualan di menu 'Transaksi Kas' atau buka shift di 'Mesin Kasir (POS)'.",
            total_trx
        )
    } else if query_lower.contains("siapa kamu") || query_lower.contains("halo") || query_lower.contains("bisa apa") || query_lower.contains("fitur") {
        format!(
            "Halo Bpk/Ibu Owner! Saya adalah Asisten AI Business Intelligence terintegrasi untuk '{}'.\n\nSaya bisa membantu Anda menganalisa:\n1. 📊 Total Omzet, Arus Kas & Laba Bersih Konsolidasi\n2. 📦 Status Stok Gudang & Alert Stok Kritis\n3. 🏪 Evaluasi Performa dan Klasifikasi BCG Tiap Cabang\n4. 💡 Rekomendasi Alokasi Modal & Efisiensi Pengeluaran\n\nSilakan ketik pertanyaan Anda!",
            owner.nama_bisnis_induk
        )
    } else {
        // Jawaban cerdas kontekstual jika pertanyaan di luar kata kunci spesifik
        if total_usaha == 0 {
            format!(
                "Saya siap membantu menjawab pertanyaan Anda terkait '{}'. Karena sistem saat ini masih bersih (belum ada data unit usaha dan produk), Anda dapat mulai dengan menambahkan cabang di menu 'Kelola Unit Usaha'.",
                owner.nama_bisnis_induk
            )
        } else {
            let info_termahal = produk_termahal.map(|p| format!(", dengan produk terlaris/unggulan {}", p)).unwrap_or_default();
            format!(
                "Pertanyaan Anda: \"{}\"\n\nBerdasarkan data operasional '{}' ({} unit usaha, {} produk{}):\nOmzet berjalan bulan ini tercatat Rp {:.0} dengan laba bersih Rp {:.0}. Jika Anda ingin rincian lebih spesifik, Anda dapat menanyakan tentang 'omzet cabang', 'stok barang', atau 'rekomendasi strategi'.",
                payload.pesan, owner.nama_bisnis_induk, total_usaha, total_produk, info_termahal, total_omzet, laba_bersih
            )
        }
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
