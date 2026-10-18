use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use serde::Deserialize;
use std::sync::Arc;
use chrono::Local;

use crate::auth::extract_claims;
use crate::models::{
    AuditLogModel, ItemCheckout, JenisTransaksi, ShiftKasirModel, StatusShift, TransaksiModel,
};
use crate::schemas::{
    ApiResponse, BukaShiftRequest, CheckoutRequest, CreateTransaksiManualRequest, TutupShiftRequest,
};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct TransaksiQuery {
    pub unit_id: Option<i64>,
    pub jenis: Option<String>,
}

// 1. STATUS SHIFT KASIR AKTIF
pub async fn get_shift_status(
    State(state): State<Arc<AppState>>,
    Path(unit_id): Path<i64>,
) -> impl IntoResponse {
    let shifts = state.shifts.read().await;

    let active_shift = shifts
        .iter()
        .find(|s| s.unit_id == unit_id && s.status == StatusShift::Open)
        .cloned();

    (
        StatusCode::OK,
        Json(ApiResponse::<Option<ShiftKasirModel>> {
            status: "success".to_string(),
            message: if active_shift.is_some() {
                "Shift kasir aktif ditemukan.".to_string()
            } else {
                "Tidak ada shift kasir yang sedang buka.".to_string()
            },
            data: Some(active_shift),
        }),
    )
}

// 2. BUKA SHIFT KASIR
pub async fn buka_shift(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<BukaShiftRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let kasir_id = claims.as_ref().map(|c| c.user_id).unwrap_or(2);
    let kasir_nama = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_else(|| "Andi Kasir".to_string());
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    // Cek apakah unit usaha punya fitur POS
    let usahas = state.usahas.read().await;
    let usaha = match usahas.iter().find(|u| u.id == payload.unit_id) {
        Some(u) => u.clone(),
        None => {
            return (
                StatusCode::NOT_FOUND,
                Json(ApiResponse::<ShiftKasirModel> {
                    status: "error".to_string(),
                    message: "Unit usaha tidak ditemukan.".to_string(),
                    data: None,
                }),
            );
        }
    };
    if !usaha.has_pos {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<ShiftKasirModel> {
                status: "error".to_string(),
                message: format!("Unit usaha '{}' tidak menggunakan sistem kasir POS.", usaha.nama),
                data: None,
            }),
        );
    }
    drop(usahas);

    let mut shifts = state.shifts.write().await;
    // Cek apakah sudah ada shift yang terbuka di unit ini
    if shifts.iter().any(|s| s.unit_id == payload.unit_id && s.status == StatusShift::Open) {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<ShiftKasirModel> {
                status: "error".to_string(),
                message: "Masih terdapat shift kasir yang aktif untuk unit ini. Tutup shift terlebih dahulu.".to_string(),
                data: None,
            }),
        );
    }

    let new_id = (shifts.len() as i64) + 1;
    let waktu_now = Local::now().format("%Y-%m-%d %H:%M").to_string();

    let new_shift = ShiftKasirModel {
        id: new_id,
        unit_id: payload.unit_id,
        kasir_id,
        nama_kasir: kasir_nama.clone(),
        modal_awal: payload.modal_awal,
        total_penjualan_tunai: 0.0,
        total_penjualan_non_tunai: 0.0,
        total_transaksi: 0,
        waktu_buka: waktu_now.clone(),
        waktu_tutup: None,
        status: StatusShift::Open,
    };

    shifts.push(new_shift.clone());
    drop(shifts);

    // Audit log
    let mut logs = state.audit_logs.write().await;
    let log_id = (logs.len() as i64) + 1;
    logs.push(AuditLogModel {
        id: log_id,
        owner_id,
        aktor: kasir_nama,
        role: "kasir".to_string(),
        aksi: "Buka Shift".to_string(),
        modul: "POS".to_string(),
        target: usaha.nama,
        detail: format!("Membuka shift kasir dengan modal awal Rp {:.0}", payload.modal_awal),
        waktu: waktu_now,
    });

    (
        StatusCode::CREATED,
        Json(ApiResponse::<ShiftKasirModel> {
            status: "success".to_string(),
            message: "Shift kasir berhasil dibuka.".to_string(),
            data: Some(new_shift),
        }),
    )
}

// 3. TUTUP SHIFT KASIR
pub async fn tutup_shift(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<TutupShiftRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let aktor_nama = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_else(|| "Kasir".to_string());
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    let mut shifts = state.shifts.write().await;
    if let Some(s) = shifts.iter_mut().find(|s| s.id == payload.shift_id) {
        if s.status == StatusShift::Closed {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<ShiftKasirModel> {
                    status: "error".to_string(),
                    message: "Shift ini sudah ditutup sebelumnya.".to_string(),
                    data: None,
                }),
            );
        }

        let waktu_tutup = Local::now().format("%Y-%m-%d %H:%M").to_string();
        s.status = StatusShift::Closed;
        s.waktu_tutup = Some(waktu_tutup.clone());

        let total_omzet = s.total_penjualan_tunai + s.total_penjualan_non_tunai;
        let shift_hasil = s.clone();
        drop(shifts);

        // Audit Log
        let mut logs = state.audit_logs.write().await;
        let log_id = (logs.len() as i64) + 1;
        logs.push(AuditLogModel {
            id: log_id,
            owner_id,
            aktor: aktor_nama,
            role: "kasir".to_string(),
            aksi: "Tutup Shift".to_string(),
            modul: "POS".to_string(),
            target: format!("Shift #{}", payload.shift_id),
            detail: format!(
                "Shift ditutup. Total transaksi: {}, Total omzet: Rp {:.0} (Tunai: Rp {:.0}, Non-Tunai: Rp {:.0})",
                shift_hasil.total_transaksi, total_omzet, shift_hasil.total_penjualan_tunai, shift_hasil.total_penjualan_non_tunai
            ),
            waktu: waktu_tutup,
        });

        return (
            StatusCode::OK,
            Json(ApiResponse::<ShiftKasirModel> {
                status: "success".to_string(),
                message: "Shift kasir berhasil ditutup dan laporan kasir telah digenerate.".to_string(),
                data: Some(shift_hasil),
            }),
        );
    }

    (
        StatusCode::NOT_FOUND,
        Json(ApiResponse::<ShiftKasirModel> {
            status: "error".to_string(),
            message: "Shift kasir tidak ditemukan.".to_string(),
            data: None,
        }),
    )
}

// 4. CHECKOUT TRANSAKSI KASIR (Atomic decrement stock + Catat Transaksi + Update Shift)
pub async fn checkout_pos(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CheckoutRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);
    let kasir_nama = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_else(|| "Kasir POS".to_string());

    if payload.items.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<TransaksiModel> {
                status: "error".to_string(),
                message: "Keranjang belanja tidak boleh kosong.".to_string(),
                data: None,
            }),
        );
    }

    // 1. Cek unit usaha & status POS
    let mut usahas = state.usahas.write().await;
    let nama_unit = match usahas.iter().find(|u| u.id == payload.unit_id) {
        Some(u) => {
            if !u.has_pos {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(ApiResponse::<TransaksiModel> {
                        status: "error".to_string(),
                        message: format!("Unit usaha '{}' dinonaktifkan dari fitur POS Kasir.", u.nama),
                        data: None,
                    }),
                );
            }
            u.nama.clone()
        }
        None => {
            return (
                StatusCode::NOT_FOUND,
                Json(ApiResponse::<TransaksiModel> {
                    status: "error".to_string(),
                    message: "Unit usaha tidak ditemukan.".to_string(),
                    data: None,
                }),
            );
        }
    };

    // 2. Validasi stok produk
    let mut produks = state.produks.write().await;
    for item in &payload.items {
        let p = match produks.iter().find(|p| p.id == item.produk_id) {
            Some(prod) => prod,
            None => {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(ApiResponse::<TransaksiModel> {
                        status: "error".to_string(),
                        message: format!("Produk ID #{} tidak ditemukan.", item.produk_id),
                        data: None,
                    }),
                );
            }
        };

        if p.stok < item.jumlah {
            return (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<TransaksiModel> {
                    status: "error".to_string(),
                    message: format!(
                        "Stok produk '{}' tidak mencukupi (Tersedia: {}, Diminta: {}).",
                        p.nama, p.stok, item.jumlah
                    ),
                    data: None,
                }),
            );
        }
    }

    // 3. Potong stok produk dan hitung total
    let mut item_checkouts: Vec<ItemCheckout> = Vec::new();
    let mut total_belanja: f64 = 0.0;

    for item in &payload.items {
        if let Some(p) = produks.iter_mut().find(|p| p.id == item.produk_id) {
            p.stok -= item.jumlah;
            let subtotal = p.harga_jual * (item.jumlah as f64);
            total_belanja += subtotal;

            item_checkouts.push(ItemCheckout {
                produk_id: p.id,
                nama_produk: p.nama.clone(),
                harga_satuan: p.harga_jual,
                jumlah: item.jumlah,
                subtotal,
            });
        }
    }
    drop(produks);

    // 4. Update pendapatan unit usaha
    if let Some(u) = usahas.iter_mut().find(|u| u.id == payload.unit_id) {
        u.pendapatan_bulan_ini += total_belanja;
    }
    drop(usahas);

    let waktu_transaksi = Local::now().format("%Y-%m-%d %H:%M").to_string();

    // 5. Update shift kasir jika ada shift aktif
    let is_tunai = payload.metode_pembayaran.to_lowercase().contains("tunai")
        || payload.metode_pembayaran.to_lowercase().contains("cash");

    let mut shifts = state.shifts.write().await;
    if let Some(s) = shifts
        .iter_mut()
        .find(|s| s.unit_id == payload.unit_id && s.status == StatusShift::Open)
    {
        if is_tunai {
            s.total_penjualan_tunai += total_belanja;
        } else {
            s.total_penjualan_non_tunai += total_belanja;
        }
        s.total_transaksi += 1;
    }
    drop(shifts);

    // 6. Catat Transaksi Penjualan
    let mut transaksis = state.transaksis.write().await;
    let trx_id = (transaksis.len() as i64) + 1;

    let keterangan = payload.keterangan.unwrap_or_else(|| {
        format!(
            "Order POS #{} ({} item) - {}",
            trx_id,
            item_checkouts.len(),
            payload.metode_pembayaran
        )
    });

    let new_trx = TransaksiModel {
        id: trx_id,
        owner_id,
        unit_id: payload.unit_id,
        nama_unit: nama_unit.clone(),
        tanggal: waktu_transaksi.clone(),
        jenis: JenisTransaksi::Pemasukan,
        kategori: "Penjualan POS".to_string(),
        jumlah: total_belanja,
        keterangan,
        metode_pembayaran: Some(payload.metode_pembayaran),
        items: Some(item_checkouts),
    };

    transaksis.push(new_trx.clone());
    drop(transaksis);

    // 7. Catat Audit Log
    let mut logs = state.audit_logs.write().await;
    let log_id = (logs.len() as i64) + 1;
    logs.push(AuditLogModel {
        id: log_id,
        owner_id,
        aktor: kasir_nama,
        role: "kasir".to_string(),
        aksi: "Transaksi POS".to_string(),
        modul: "Kasir".to_string(),
        target: nama_unit,
        detail: format!("Transaksi Penjualan #{} sukses senilai Rp {:.0}", trx_id, total_belanja),
        waktu: waktu_transaksi,
    });

    (
        StatusCode::CREATED,
        Json(ApiResponse::<TransaksiModel> {
            status: "success".to_string(),
            message: "Transaksi kasir berhasil diselesaikan dan stok telah dipotong secara real-time.".to_string(),
            data: Some(new_trx),
        }),
    )
}

// 5. RIWAYAT TRANSAKSI (Filter unit_id & jenis)
pub async fn list_transaksi(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Query(query): Query<TransaksiQuery>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    let transaksis = state.transaksis.read().await;

    let hasil: Vec<TransaksiModel> = transaksis
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
            if let Some(j) = &query.jenis {
                let j_lower = j.to_lowercase();
                if j_lower == "pemasukan" && t.jenis != JenisTransaksi::Pemasukan {
                    return false;
                }
                if j_lower == "pengeluaran" && t.jenis != JenisTransaksi::Pengeluaran {
                    return false;
                }
            }
            true
        })
        .cloned()
        .collect();

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<TransaksiModel>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} transaksi.", hasil.len()),
            data: Some(hasil),
        }),
    )
}

// 6. CATAT TRANSAKSI MANUAL (Pemasukan / Pengeluaran Umum)
pub async fn create_transaksi_manual(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreateTransaksiManualRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);
    let aktor_nama = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_else(|| "User Demo".to_string());
    let aktor_role = claims.as_ref().map(|c| c.role.clone()).unwrap_or_else(|| "manager".to_string());

    let mut usahas = state.usahas.write().await;
    let nama_unit = match usahas.iter_mut().find(|u| u.id == payload.unit_id) {
        Some(u) => {
            if payload.jenis == JenisTransaksi::Pemasukan {
                u.pendapatan_bulan_ini += payload.jumlah;
            } else {
                u.pengeluaran_bulan_ini += payload.jumlah;
            }
            u.nama.clone()
        }
        None => {
            return (
                StatusCode::NOT_FOUND,
                Json(ApiResponse::<TransaksiModel> {
                    status: "error".to_string(),
                    message: "Unit usaha tidak ditemukan.".to_string(),
                    data: None,
                }),
            );
        }
    };
    drop(usahas);

    let mut transaksis = state.transaksis.write().await;
    let new_id = (transaksis.len() as i64) + 1;
    let waktu_now = Local::now().format("%Y-%m-%d %H:%M").to_string();

    let new_trx = TransaksiModel {
        id: new_id,
        owner_id,
        unit_id: payload.unit_id,
        nama_unit: nama_unit.clone(),
        tanggal: waktu_now.clone(),
        jenis: payload.jenis.clone(),
        kategori: payload.kategori,
        jumlah: payload.jumlah,
        keterangan: payload.keterangan,
        metode_pembayaran: Some("Manual".to_string()),
        items: None,
    };

    transaksis.push(new_trx.clone());
    drop(transaksis);

    // Audit Log
    let mut logs = state.audit_logs.write().await;
    let log_id = (logs.len() as i64) + 1;
    logs.push(AuditLogModel {
        id: log_id,
        owner_id,
        aktor: aktor_nama,
        role: aktor_role,
        aksi: format!("Catat Transaksi {:?}", payload.jenis),
        modul: "Keuangan".to_string(),
        target: nama_unit,
        detail: format!("Transaksi #{:?} senilai Rp {:.0}", new_id, payload.jumlah),
        waktu: waktu_now,
    });

    (
        StatusCode::CREATED,
        Json(ApiResponse::<TransaksiModel> {
            status: "success".to_string(),
            message: "Transaksi berhasil dicatat dan keuangan unit usaha telah disinkronkan.".to_string(),
            data: Some(new_trx),
        }),
    )
}
