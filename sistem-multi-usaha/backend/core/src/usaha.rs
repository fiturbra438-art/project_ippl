use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use rust_decimal::prelude::ToPrimitive;
use rust_decimal::Decimal;
use std::sync::Arc;

use crate::models::{Claims, PaketLangganan, UsahaModel};
use crate::schemas::{ApiResponse, CreateUsahaRequest, UpdateUsahaRequest};
use crate::state::AppState;

fn normalize_kategori_portofolio(raw: Option<&str>) -> String {
    match raw.unwrap_or("Star").trim().to_lowercase().as_str() {
        "star" => "Star".to_string(),
        "cash_cow" | "cash cow" => "Cash Cow".to_string(),
        "question_mark" | "question mark" => "Question Mark".to_string(),
        "dog" => "Dog".to_string(),
        other if !other.is_empty() => raw.unwrap_or("Star").to_string(),
        _ => "Star".to_string(),
    }
}

type UsahaRow = (
    i32,
    i32,
    String,
    String,
    Option<String>,
    Option<String>,
    bool,
    Option<bool>,
    Option<Decimal>,
    Option<Decimal>,
    Option<Decimal>,
);

fn map_usaha_row(u: UsahaRow) -> UsahaModel {
    UsahaModel {
        id: u.0 as i64,
        owner_id: u.1 as i64,
        nama: u.2,
        jenis_usaha: u.3,
        lokasi: u.4.unwrap_or_default(),
        kategori_portofolio: normalize_kategori_portofolio(u.5.as_deref()),
        status: u.6,
        has_pos: u.7.unwrap_or(true),
        pendapatan_bulan_ini: u.8.and_then(|d| d.to_f64()).unwrap_or(0.0),
        pengeluaran_bulan_ini: u.9.and_then(|d| d.to_f64()).unwrap_or(0.0),
        pertumbuhan_persen: u.10.and_then(|d| d.to_f64()).unwrap_or(0.0),
    }
}

// 1. LIST UNIT USAHA (Strict Authentication via PostgreSQL)
pub async fn list_usaha(
    State(state): State<Arc<AppState>>,
    claims: Claims,
) -> impl IntoResponse {
    let owner_id = claims.owner_id as i32;
    let role = claims.role.as_str();

    let rows: Vec<UsahaRow> = if role == "owner" || role == "auditor" {
        sqlx::query_as(
            "SELECT id, owner_id, nama, jenis_usaha, lokasi, kategori_portofolio, status, has_pos,
                    pendapatan_bulan_ini, pengeluaran_bulan_ini, pertumbuhan_persen
             FROM business_units
             WHERE owner_id = $1
             ORDER BY id ASC",
        )
        .bind(owner_id)
        .fetch_all(&state.db)
        .await
        .unwrap_or_default()
    } else {
        sqlx::query_as(
            "SELECT u.id, u.owner_id, u.nama, u.jenis_usaha, u.lokasi, u.kategori_portofolio, u.status, u.has_pos,
                    u.pendapatan_bulan_ini, u.pengeluaran_bulan_ini, u.pertumbuhan_persen
             FROM business_units u
             WHERE u.owner_id = $1
               AND (
                   NOT EXISTS (SELECT 1 FROM user_units WHERE user_id = $2)
                   OR EXISTS (SELECT 1 FROM user_units uu WHERE uu.user_id = $2 AND uu.unit_id = u.id)
               )
             ORDER BY u.id ASC",
        )
        .bind(owner_id)
        .bind(claims.user_id as i32)
        .fetch_all(&state.db)
        .await
        .unwrap_or_default()
    };

    let hasil: Vec<UsahaModel> = rows.into_iter().map(map_usaha_row).collect();

    (
        StatusCode::OK,
        Json(ApiResponse::<Vec<UsahaModel>> {
            status: "success".to_string(),
            message: format!("Berhasil mengambil {} unit usaha.", hasil.len()),
            data: Some(hasil),
        }),
    )
        .into_response()
}

// 2. DETAIL UNIT USAHA (Dilindungi Validasi Kepemilikan)
pub async fn get_usaha_detail(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    let row = sqlx::query_as::<_, UsahaRow>(
        "SELECT id, owner_id, nama, jenis_usaha, lokasi, kategori_portofolio, status, has_pos,
                pendapatan_bulan_ini, pengeluaran_bulan_ini, pertumbuhan_persen
         FROM business_units 
         WHERE id = $1 AND owner_id = $2",
    )
    .bind(id as i32)
    .bind(claims.owner_id as i32)
    .fetch_optional(&state.db)
    .await;

    match row {
        Ok(Some(u)) => (
            StatusCode::OK,
            Json(ApiResponse::<UsahaModel> {
                status: "success".to_string(),
                message: "Detail unit usaha ditemukan.".to_string(),
                data: Some(map_usaha_row(u)),
            }),
        )
            .into_response(),
        _ => (
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<UsahaModel> {
                status: "error".to_string(),
                message: "Unit usaha tidak ditemukan atau Anda tidak memiliki hak akses."
                    .to_string(),
                data: None,
            }),
        )
            .into_response(),
    }
}

// 3. TAMBAH UNIT USAHA (Cek Kuota Tier Langganan)
pub async fn create_usaha(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Json(payload): Json<CreateUsahaRequest>,
) -> impl IntoResponse {
    let owner_id = claims.owner_id;
    let aktor_nama = claims.sub.clone();
    let aktor_role = claims.role.clone();

    if !["owner", "manager"].contains(&aktor_role.as_str()) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<UsahaModel> {
                status: "error".to_string(),
                message: "Role Anda tidak berwenang menambah unit usaha.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    // Cek kuota tier owner langsung dari PostgreSQL
    let owner_row: Option<(Option<String>, Option<i32>)> = sqlx::query_as(
        "SELECT tier, kuota_unit_usaha FROM users WHERE id = $1 AND role = 'owner'",
    )
    .bind(owner_id as i32)
    .fetch_optional(&state.db)
    .await
    .unwrap_or(None);

    let (tier_opt, kuota_opt) = match owner_row {
        Some(r) => r,
        None => {
            return (
                StatusCode::FORBIDDEN,
                Json(ApiResponse::<UsahaModel> {
                    status: "error".to_string(),
                    message: "Akun owner tidak valid.".to_string(),
                    data: None,
                }),
            )
                .into_response();
        }
    };

    let paket_langganan = match tier_opt.as_deref() {
        Some("enterprise") => PaketLangganan::Enterprise,
        Some("pro") => PaketLangganan::Pro,
        _ => PaketLangganan::Free,
    };
    let kuota_unit_usaha = kuota_opt.unwrap_or(5);

    let current_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM business_units WHERE owner_id = $1",
    )
    .bind(owner_id as i32)
    .fetch_one(&state.db)
    .await
    .unwrap_or(0);

    if current_count >= (kuota_unit_usaha as i64) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<UsahaModel> {
                status: "error".to_string(),
                message: format!(
                    "Batas kuota paket ({:?}) telah tercapai (Maksimal {} unit usaha). Silakan upgrade paket ke Pro atau Enterprise untuk menambah cabang baru.",
                    paket_langganan, kuota_unit_usaha
                ),
                data: None,
            }),
        )
            .into_response();
    }

    let kategori_norm = normalize_kategori_portofolio(payload.kategori_portofolio.as_deref());

    // Simpan permanen ke PostgreSQL
    let row_id: Result<(i32,), sqlx::Error> = sqlx::query_as(
        "INSERT INTO business_units (owner_id, nama, jenis_usaha, lokasi, kategori_portofolio, status, has_pos)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING id",
    )
    .bind(owner_id as i32)
    .bind(&payload.nama)
    .bind(&payload.jenis_usaha)
    .bind(&payload.lokasi)
    .bind(&kategori_norm)
    .bind(true)
    .bind(payload.has_pos.unwrap_or(true))
    .fetch_one(&state.db)
    .await;

    let new_id = match row_id {
        Ok(r) => r.0 as i64,
        Err(e) => {
            tracing::error!("Gagal menyimpan unit usaha baru: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<UsahaModel> {
                    status: "error".to_string(),
                    message: "Gagal menyimpan unit usaha baru ke database.".to_string(),
                    data: None,
                }),
            )
                .into_response();
        }
    };

    let new_usaha = UsahaModel {
        id: new_id,
        owner_id,
        nama: payload.nama.clone(),
        jenis_usaha: payload.jenis_usaha,
        lokasi: payload.lokasi,
        kategori_portofolio: kategori_norm,
        pendapatan_bulan_ini: 0.0,
        pengeluaran_bulan_ini: 0.0,
        pertumbuhan_persen: 0.0,
        status: true,
        has_pos: payload.has_pos.unwrap_or(true),
    };

    // Simpan Audit Log langsung ke PostgreSQL
    let _ = sqlx::query(
        "INSERT INTO audit_logs (owner_id, aktor, role, aksi, modul, target, detail, waktu)
         VALUES ($1, $2, $3, 'Tambah Unit Usaha', 'Unit Usaha', $4, $5, now())",
    )
    .bind(owner_id as i32)
    .bind(&aktor_nama)
    .bind(&aktor_role)
    .bind(&payload.nama)
    .bind(format!("Berhasil membuat unit usaha baru ID #{}", new_id))
    .execute(&state.db)
    .await;

    (
        StatusCode::CREATED,
        Json(ApiResponse::<UsahaModel> {
            status: "success".to_string(),
            message: "Unit usaha baru berhasil didaftarkan.".to_string(),
            data: Some(new_usaha),
        }),
    )
        .into_response()
}

// 4. UPDATE UNIT USAHA (Dilindungi Validasi IDOR)
pub async fn update_usaha(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Path(id): Path<i64>,
    Json(payload): Json<UpdateUsahaRequest>,
) -> impl IntoResponse {
    if !["owner", "manager"].contains(&claims.role.as_str()) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<UsahaModel> {
                status: "error".to_string(),
                message: "Role Anda tidak berwenang mengubah unit usaha.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    let existing = sqlx::query_as::<_, UsahaRow>(
        "SELECT id, owner_id, nama, jenis_usaha, lokasi, kategori_portofolio, status, has_pos,
                pendapatan_bulan_ini, pengeluaran_bulan_ini, pertumbuhan_persen
         FROM business_units
         WHERE id = $1 AND owner_id = $2",
    )
    .bind(id as i32)
    .bind(claims.owner_id as i32)
    .fetch_optional(&state.db)
    .await;

    let mut u = match existing {
        Ok(Some(row)) => map_usaha_row(row),
        _ => {
            return (
                StatusCode::FORBIDDEN,
                Json(ApiResponse::<UsahaModel> {
                    status: "error".to_string(),
                    message:
                        "Akses ditolak: Anda tidak memiliki izin untuk mengedit unit usaha ini."
                            .to_string(),
                    data: None,
                }),
            )
                .into_response();
        }
    };

    if let Some(nama) = payload.nama {
        u.nama = nama;
    }
    if let Some(jenis) = payload.jenis_usaha {
        u.jenis_usaha = jenis;
    }
    if let Some(lokasi) = payload.lokasi {
        u.lokasi = lokasi;
    }
    if let Some(kat) = payload.kategori_portofolio {
        u.kategori_portofolio = normalize_kategori_portofolio(Some(&kat));
    }
    if let Some(status) = payload.status {
        u.status = status;
    }
    if let Some(has_pos) = payload.has_pos {
        u.has_pos = has_pos;
    }

    let _ = sqlx::query(
        "UPDATE business_units
         SET nama = $1, jenis_usaha = $2, lokasi = $3, kategori_portofolio = $4, status = $5, has_pos = $6
         WHERE id = $7 AND owner_id = $8",
    )
    .bind(&u.nama)
    .bind(&u.jenis_usaha)
    .bind(&u.lokasi)
    .bind(&u.kategori_portofolio)
    .bind(u.status)
    .bind(u.has_pos)
    .bind(id as i32)
    .bind(claims.owner_id as i32)
    .execute(&state.db)
    .await;

    (
        StatusCode::OK,
        Json(ApiResponse::<UsahaModel> {
            status: "success".to_string(),
            message: "Data unit usaha berhasil diperbarui.".to_string(),
            data: Some(u),
        }),
    )
        .into_response()
}

// 5. TOGGLE STATUS POS (Dilindungi Validasi IDOR)
pub async fn toggle_pos(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    if !["owner", "manager"].contains(&claims.role.as_str()) {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<UsahaModel> {
                status: "error".to_string(),
                message: "Role Anda tidak berwenang mengubah status POS.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    let updated = sqlx::query_as::<_, UsahaRow>(
        "UPDATE business_units
         SET has_pos = NOT COALESCE(has_pos, true)
         WHERE id = $1 AND owner_id = $2
         RETURNING id, owner_id, nama, jenis_usaha, lokasi, kategori_portofolio, status, has_pos,
                   pendapatan_bulan_ini, pengeluaran_bulan_ini, pertumbuhan_persen",
    )
    .bind(id as i32)
    .bind(claims.owner_id as i32)
    .fetch_optional(&state.db)
    .await;

    if let Ok(Some(row)) = updated {
        let u = map_usaha_row(row);
        let status_str = if u.has_pos { "Aktif" } else { "Non-Aktif" };
        return (
            StatusCode::OK,
            Json(ApiResponse::<UsahaModel> {
                status: "success".to_string(),
                message: format!("Fitur Kasir POS untuk {} kini: {}", u.nama, status_str),
                data: Some(u),
            }),
        )
            .into_response();
    }

    (
        StatusCode::FORBIDDEN,
        Json(ApiResponse::<UsahaModel> {
            status: "error".to_string(),
            message: "Unit usaha tidak ditemukan atau Anda tidak memiliki hak akses.".to_string(),
            data: None,
        }),
    )
        .into_response()
}

// 6. HAPUS UNIT USAHA (Dilindungi Validasi IDOR)
pub async fn delete_usaha(
    State(state): State<Arc<AppState>>,
    claims: Claims,
    Path(id): Path<i64>,
) -> impl IntoResponse {
    if claims.role != "owner" {
        return (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message: "Hanya pemilik bisnis yang boleh menghapus unit usaha.".to_string(),
                data: None,
            }),
        )
            .into_response();
    }

    let res = sqlx::query("DELETE FROM business_units WHERE id = $1 AND owner_id = $2")
        .bind(id as i32)
        .bind(claims.owner_id as i32)
        .execute(&state.db)
        .await;

    match res {
        Ok(r) if r.rows_affected() > 0 => (
            StatusCode::OK,
            Json(ApiResponse::<()> {
                status: "success".to_string(),
                message: format!("Unit usaha #{} berhasil dihapus permanen.", id),
                data: None,
            }),
        )
            .into_response(),
        _ => (
            StatusCode::FORBIDDEN,
            Json(ApiResponse::<()> {
                status: "error".to_string(),
                message:
                    "Gagal menghapus: Unit usaha tidak ditemukan atau Anda bukan pemilik unit ini."
                        .to_string(),
                data: None,
            }),
        )
            .into_response(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_kategori_portofolio() {
        assert_eq!(normalize_kategori_portofolio(Some("star")), "Star");
        assert_eq!(normalize_kategori_portofolio(Some("Star")), "Star");
        assert_eq!(normalize_kategori_portofolio(Some("cash_cow")), "Cash Cow");
        assert_eq!(
            normalize_kategori_portofolio(Some("question_mark")),
            "Question Mark"
        );
        assert_eq!(normalize_kategori_portofolio(Some("dog")), "Dog");
        assert_eq!(normalize_kategori_portofolio(None), "Star");
    }
}
