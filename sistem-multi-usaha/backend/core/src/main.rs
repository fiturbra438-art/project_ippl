mod ai;
mod auth;
mod dashboard;
mod gudang;
mod karyawan;
mod models;
mod pos;
mod produk;
mod schemas;
mod state;
mod usaha;

use axum::{
    routing::{get, patch, post, put},
    Router,
};
use state::AppState;
use std::sync::Arc;
use tower_http::cors::{Any, CorsLayer};
use tower_http::services::{ServeDir, ServeFile};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Load .env
    dotenvy::dotenv().ok();
    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgresql://usaha_user:Fitur1206@localhost:5432/usaha_db".to_string());

    tracing::info!("🔌 Menghubungkan ke PostgreSQL: {}", database_url);
    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(10)
        .connect(&database_url)
        .await
        .expect("Gagal terhubung ke database PostgreSQL!");

    let shared_state = Arc::new(AppState::new(pool).await);

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    // Folder hasil build web Flutter. Bisa dioverride lewat env WEB_DIR.
    let web_dir = std::env::var("WEB_DIR").unwrap_or_else(|_| {
        format!("{}/../../frontend/build/web", env!("CARGO_MANIFEST_DIR"))
    });
    let index_file = format!("{}/index.html", web_dir);
    let serve_dir = ServeDir::new(&web_dir).fallback(ServeFile::new(&index_file));

    let app = Router::new()
        // Health Check
        .route("/health", get(|| async { "Rust Core Backend OK" }))

        // ==================== 1. MODUL AUTENTIKASI ====================
        .route("/api/auth/owner/register", post(auth::register_owner))
        .route("/api/auth/owner/login", post(auth::login_owner))
        .route("/api/auth/owner/verify-2fa", post(auth::verify_owner_2fa))
        .route("/api/auth/owner/upgrade-tier", post(auth::upgrade_owner_tier))
        .route("/api/auth/karyawan/login", post(auth::login_karyawan))

        // ==================== 2. MODUL UNIT USAHA ====================
        .route("/api/usaha", get(usaha::list_usaha).post(usaha::create_usaha))
        .route(
            "/api/usaha/:id",
            get(usaha::get_usaha_detail)
                .put(usaha::update_usaha)
                .delete(usaha::delete_usaha),
        )
        .route("/api/usaha/:id/toggle-pos", patch(usaha::toggle_pos))

        // ==================== 3. MODUL PRODUK & STOK ====================
        .route("/api/produk", get(produk::list_produk).post(produk::create_produk))
        .route("/api/produk/low-stock", get(produk::list_low_stock))
        .route(
            "/api/produk/:id",
            get(produk::get_produk_detail)
                .put(produk::update_produk)
                .delete(produk::delete_produk),
        )
        .route("/api/produk/:id/stok", patch(produk::adjust_stok))

        // ==================== 4. MODUL POS & TRANSAKSI ====================
        .route("/api/pos/shift/:unit_id", get(pos::get_shift_status))
        .route("/api/pos/shift/buka", post(pos::buka_shift))
        .route("/api/pos/shift/tutup", post(pos::tutup_shift))
        .route("/api/pos/checkout", post(pos::checkout_pos))
        .route("/api/transaksi", get(pos::list_transaksi).post(pos::create_transaksi_manual))

        // ==================== 5. MODUL GUDANG & PERMINTAAN STOK ====================
        .route(
            "/api/gudang/permintaan",
            get(gudang::list_permintaan_stok).post(gudang::create_permintaan_stok),
        )
        .route(
            "/api/gudang/permintaan/:id/status",
            patch(gudang::update_status_permintaan),
        )
        .route(
            "/api/gudang/opname",
            get(gudang::list_stok_opname).post(gudang::create_stok_opname),
        )
        .route(
            "/api/gudang/transfer",
            get(gudang::list_transfer_stok).post(gudang::create_transfer_stok),
        )
        .route(
            "/api/gudang/transfer/:id/status",
            patch(gudang::update_status_transfer),
        )

        // ==================== 6. MODUL DASHBOARD & LAPORAN ====================
        .route("/api/dashboard/summary", get(dashboard::get_dashboard_summary))
        .route("/api/laporan/keuangan", get(dashboard::get_laporan_keuangan))

        // ==================== 7. MODUL MANAJEMEN KARYAWAN & AUDIT ====================
        .route(
            "/api/karyawan",
            get(karyawan::list_karyawan).post(karyawan::create_karyawan),
        )
        .route(
            "/api/karyawan/:id",
            put(karyawan::update_karyawan).delete(karyawan::delete_karyawan),
        )
        .route("/api/audit-logs", get(karyawan::list_audit_logs))

        // ==================== 8. MODUL AI & ANALYTICS ====================
        .route("/api/ai/chat", post(ai::chat_ai))
        .route("/api/ai/forecast/:unit_id", get(ai::get_forecast))
        .route("/api/ai/anomali", get(ai::get_anomali))

        // Fallback Web UI Flutter
        .fallback_service(serve_dir)
        .layer(cors)
        .with_state(shared_state);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8000")
        .await
        .expect("Failed to bind port 8000");

    tracing::info!("🦀 Server Core Rust berjalan di http://0.0.0.0:8000");

    axum::serve(listener, app).await.unwrap();
}
