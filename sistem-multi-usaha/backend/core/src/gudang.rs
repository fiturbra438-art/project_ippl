use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use std::sync::Arc;
use chrono::Local;

use crate::auth::extract_claims;
use crate::models::{
    AuditLogModel, PermintaanStokModel, StatusPermintaanStok, StatusTransfer,
    StokOpnameModel, TransferStokModel,
};
use crate::schemas::{
    ApiResponse, CreatePermintaanStokRequest, CreateStokOpnameRequest,
    CreateTransferStokRequest, UpdateStatusPermintaanRequest, UpdateStatusTransferRequest,
};
use crate::state::AppState;

// ==================== 1. PERMINTAAN STOK ====================

pub async fn list_permintaan_stok(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    let requests = state.permintaan_stoks.read().await;
    let hasil: Vec<PermintaanStokModel> = requests
        .iter()
        .filter(|p| p.owner_id == owner_id)
        .cloned()
        .collect();

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<PermintaanStokModel>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} pengajuan permintaan stok.", hasil.len()),
            data: Some(hasil),
        }),
    )
}

pub async fn create_permintaan_stok(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreatePermintaanStokRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);
    let pemohon = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_else(|| "Staff Unit".to_string());
    let aktor_role = claims.as_ref().map(|c| c.role.clone()).unwrap_or_else(|| "manager".to_string());

    let usahas = state.usahas.read().await;
    let nama_unit = match usahas.iter().find(|u| u.id == payload.unit_id) {
        Some(u) => u.nama.clone(),
        None => "Unit Usaha".to_string(),
    };
    drop(usahas);

    let mut list = state.permintaan_stoks.write().await;
    let new_id = (list.len() as i64) + 1;
    let waktu_now = Local::now().format("%Y-%m-%d %H:%M").to_string();

    let new_permintaan = PermintaanStokModel {
        id: new_id,
        owner_id,
        unit_id: payload.unit_id,
        nama_unit: nama_unit.clone(),
        pemohon: pemohon.clone(),
        nama_produk: payload.nama_produk.clone(),
        jumlah_diminta: payload.jumlah_diminta,
        alasan: payload.alasan.clone(),
        waktu_pengajuan: waktu_now.clone(),
        status: StatusPermintaanStok::Pending,
    };

    list.push(new_permintaan.clone());
    drop(list);

    // Audit log
    let mut logs = state.audit_logs.write().await;
    let log_id = (logs.len() as i64) + 1;
    logs.push(AuditLogModel {
        id: log_id,
        owner_id,
        aktor: pemohon,
        role: aktor_role,
        aksi: "Ajukan Permintaan Stok".to_string(),
        modul: "Gudang".to_string(),
        target: format!("{}: {}", nama_unit, payload.nama_produk),
        detail: format!("Mengajukan {} unit. Alasan: {}", payload.jumlah_diminta, payload.alasan),
        waktu: waktu_now,
    });

    (
        StatusCode::CREATED,
        Json(ApiResponse::<PermintaanStokModel> {
            status: "success".to_string(),
            message: "Pengajuan permintaan stok berhasil dikirim ke Admin Gudang / Owner.".to_string(),
            data: Some(new_permintaan),
        }),
    )
}

pub async fn update_status_permintaan(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<UpdateStatusPermintaanRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let aktor_nama = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_else(|| "Admin Gudang".to_string());
    let aktor_role = claims.as_ref().map(|c| c.role.clone()).unwrap_or_else(|| "admin_gudang".to_string());
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    let mut list = state.permintaan_stoks.write().await;
    if let Some(p) = list.iter_mut().find(|p| p.id == id) {
        p.status = payload.status.clone();
        let updated = p.clone();
        drop(list);

        // Audit Log
        let mut logs = state.audit_logs.write().await;
        let log_id = (logs.len() as i64) + 1;
        logs.push(AuditLogModel {
            id: log_id,
            owner_id,
            aktor: aktor_nama,
            role: aktor_role,
            aksi: "Ubah Status Permintaan".to_string(),
            modul: "Gudang".to_string(),
            target: format!("Permintaan #{}", id),
            detail: format!("Status diubah menjadi: {:?}", payload.status),
            waktu: Local::now().format("%Y-%m-%d %H:%M").to_string(),
        });

        return (
            StatusCode::OK,
            Json(ApiResponse::<PermintaanStokModel> {
                status: "success".to_string(),
                message: format!("Status permintaan stok #{} berhasil diubah.", id),
                data: Some(updated),
            }),
        );
    }

    (
        StatusCode::NOT_FOUND,
        Json(ApiResponse::<PermintaanStokModel> {
            status: "error".to_string(),
            message: "Permintaan stok tidak ditemukan.".to_string(),
            data: None,
        }),
    )
}

// ==================== 2. STOK OPNAME ====================

pub async fn list_stok_opname(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    let opnames = state.stok_opnames.read().await;
    let hasil: Vec<StokOpnameModel> = opnames
        .iter()
        .filter(|o| o.owner_id == owner_id)
        .cloned()
        .collect();

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<StokOpnameModel>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} riwayat stok opname.", hasil.len()),
            data: Some(hasil),
        }),
    )
}

pub async fn create_stok_opname(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreateStokOpnameRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);
    let aktor_nama = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_else(|| "Auditor / Gudang".to_string());
    let aktor_role = claims.as_ref().map(|c| c.role.clone()).unwrap_or_else(|| "admin_gudang".to_string());

    let usahas = state.usahas.read().await;
    let nama_unit = match usahas.iter().find(|u| u.id == payload.unit_id) {
        Some(u) => u.nama.clone(),
        None => "Unit Usaha".to_string(),
    };
    drop(usahas);

    // Cari produk untuk mengetahui stok sistem & sinkronkan stok fisik
    let mut produks = state.produks.write().await;
    let (stok_sistem, nama_produk) = match produks
        .iter_mut()
        .find(|p| p.unit_id == payload.unit_id && p.nama.to_lowercase() == payload.nama_produk.to_lowercase())
    {
        Some(p) => {
            let sistem = p.stok;
            p.stok = payload.stok_fisik; // Rekonsiliasi stok sistem ke stok fisik
            (sistem, p.nama.clone())
        }
        None => (0, payload.nama_produk),
    };
    drop(produks);

    let selisih = payload.stok_fisik - stok_sistem;
    let waktu_now = Local::now().format("%Y-%m-%d").to_string();

    let mut list = state.stok_opnames.write().await;
    let new_id = (list.len() as i64) + 1;

    let new_opname = StokOpnameModel {
        id: new_id,
        owner_id,
        unit_id: payload.unit_id,
        nama_unit: nama_unit.clone(),
        nama_produk: nama_produk.clone(),
        stok_sistem,
        stok_fisik: payload.stok_fisik,
        selisih,
        alasan: payload.alasan.clone(),
        tanggal: waktu_now.clone(),
    };

    list.push(new_opname.clone());
    drop(list);

    // Audit Log
    let mut logs = state.audit_logs.write().await;
    let log_id = (logs.len() as i64) + 1;
    logs.push(AuditLogModel {
        id: log_id,
        owner_id,
        aktor: aktor_nama,
        role: aktor_role,
        aksi: "Stok Opname".to_string(),
        modul: "Gudang".to_string(),
        target: format!("{}: {}", nama_unit, nama_produk),
        detail: format!(
            "Hasil Opname: Sistem {}, Fisik {} (Selisih: {}). Alasan: {}",
            stok_sistem, payload.stok_fisik, selisih, payload.alasan
        ),
        waktu: Local::now().format("%Y-%m-%d %H:%M").to_string(),
    });

    (
        StatusCode::CREATED,
        Json(ApiResponse::<StokOpnameModel> {
            status: "success".to_string(),
            message: "Rekonsiliasi stok opname berhasil disimpan dan stok sistem telah diperbarui.".to_string(),
            data: Some(new_opname),
        }),
    )
}

// ==================== 3. TRANSFER STOK ====================

pub async fn list_transfer_stok(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);

    let transfers = state.transfer_stoks.read().await;
    let hasil: Vec<TransferStokModel> = transfers
        .iter()
        .filter(|t| t.owner_id == owner_id)
        .cloned()
        .collect();

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<TransferStokModel>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} mutasi transfer stok.", hasil.len()),
            data: Some(hasil),
        }),
    )
}

pub async fn create_transfer_stok(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreateTransferStokRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);
    let aktor_nama = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_else(|| "Logistik".to_string());

    let usahas = state.usahas.read().await;
    let nama_asal = usahas.iter().find(|u| u.id == payload.unit_asal_id).map(|u| u.nama.clone()).unwrap_or_else(|| "Unit Asal".to_string());
    let nama_tujuan = usahas.iter().find(|u| u.id == payload.unit_tujuan_id).map(|u| u.nama.clone()).unwrap_or_else(|| "Unit Tujuan".to_string());
    drop(usahas);

    let mut produks = state.produks.write().await;
    let p_asal = match produks.iter_mut().find(|p| p.id == payload.produk_id) {
        Some(p) => {
            if p.stok < payload.jumlah {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(ApiResponse::<TransferStokModel> {
                        status: "error".to_string(),
                        message: format!("Stok di unit asal tidak mencukupi (Tersedia: {}, Diminta: {})", p.stok, payload.jumlah),
                        data: None,
                    }),
                );
            }
            p.stok -= payload.jumlah;
            p.clone()
        }
        None => {
            return (
                StatusCode::NOT_FOUND,
                Json(ApiResponse::<TransferStokModel> {
                    status: "error".to_string(),
                    message: "Produk tidak ditemukan.".to_string(),
                    data: None,
                }),
            );
        }
    };
    drop(produks);

    let mut list = state.transfer_stoks.write().await;
    let new_id = (list.len() as i64) + 1;
    let waktu_now = Local::now().format("%Y-%m-%d %H:%M").to_string();

    let new_transfer = TransferStokModel {
        id: new_id,
        owner_id,
        unit_asal_id: payload.unit_asal_id,
        nama_unit_asal: nama_asal.clone(),
        unit_tujuan_id: payload.unit_tujuan_id,
        nama_unit_tujuan: nama_tujuan.clone(),
        produk_id: payload.produk_id,
        nama_produk: p_asal.nama.clone(),
        jumlah: payload.jumlah,
        waktu_kirim: waktu_now.clone(),
        waktu_terima: None,
        status: StatusTransfer::Pending,
    };

    list.push(new_transfer.clone());
    drop(list);

    // Audit log
    let mut logs = state.audit_logs.write().await;
    let log_id = (logs.len() as i64) + 1;
    logs.push(AuditLogModel {
        id: log_id,
        owner_id,
        aktor: aktor_nama,
        role: "admin_gudang".to_string(),
        aksi: "Transfer Stok".to_string(),
        modul: "Gudang".to_string(),
        target: format!("{} -> {}", nama_asal, nama_tujuan),
        detail: format!("Mengirim {} unit produk '{}'", payload.jumlah, p_asal.nama),
        waktu: waktu_now,
    });

    (
        StatusCode::CREATED,
        Json(ApiResponse::<TransferStokModel> {
            status: "success".to_string(),
            message: "Mutasi transfer stok berhasil diproses dan stok unit asal telah dipotong.".to_string(),
            data: Some(new_transfer),
        }),
    )
}

pub async fn update_status_transfer(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<UpdateStatusTransferRequest>,
) -> impl IntoResponse {
    let claims = extract_claims(&headers, &state.jwt_secret);
    let owner_id = claims.as_ref().map(|c| c.owner_id).unwrap_or(1);
    let aktor_nama = claims.as_ref().map(|c| c.sub.clone()).unwrap_or_else(|| "Penerima".to_string());

    let mut list = state.transfer_stoks.write().await;
    if let Some(t) = list.iter_mut().find(|t| t.id == id) {
        t.status = payload.status.clone();
        let waktu_now = Local::now().format("%Y-%m-%d %H:%M").to_string();

        if payload.status == StatusTransfer::Diterima {
            t.waktu_terima = Some(waktu_now.clone());

            // Tambahkan stok ke unit tujuan
            let mut produks = state.produks.write().await;
            if let Some(p) = produks
                .iter_mut()
                .find(|p| p.unit_id == t.unit_tujuan_id && p.nama.to_lowercase() == t.nama_produk.to_lowercase())
            {
                p.stok += t.jumlah;
            }
        }

        let updated = t.clone();
        drop(list);

        // Audit Log
        let mut logs = state.audit_logs.write().await;
        let log_id = (logs.len() as i64) + 1;
        logs.push(AuditLogModel {
            id: log_id,
            owner_id,
            aktor: aktor_nama,
            role: "admin_gudang".to_string(),
            aksi: "Konfirmasi Penerimaan Transfer".to_string(),
            modul: "Gudang".to_string(),
            target: format!("Transfer #{}", id),
            detail: format!("Status diubah menjadi: {:?}", payload.status),
            waktu: waktu_now,
        });

        return (
            StatusCode::OK,
            Json(ApiResponse::<TransferStokModel> {
                status: "success".to_string(),
                message: format!("Mutasi transfer #{} berhasil dikonfirmasi.", id),
                data: Some(updated),
            }),
        );
    }

    (
        StatusCode::NOT_FOUND,
        Json(ApiResponse::<TransferStokModel> {
            status: "error".to_string(),
            message: "Mutasi transfer stok tidak ditemukan.".to_string(),
            data: None,
        }),
    )
}
