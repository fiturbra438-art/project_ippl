mod auth;
mod models;
mod schemas;
mod state;

use axum::{
    routing::{get, post},
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

    let shared_state = Arc::new(AppState::new());

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
        .route("/health", get(|| async { "Rust Core Backend OK" }))
        // Auth Owner
        .route("/api/auth/owner/register", post(auth::register_owner))
        .route("/api/auth/owner/login", post(auth::login_owner))
        .route("/api/auth/owner/verify-2fa", post(auth::verify_owner_2fa))
        .route("/api/auth/owner/upgrade-tier", post(auth::upgrade_owner_tier))
        // Auth Karyawan
        .route("/api/auth/karyawan/login", post(auth::login_karyawan))
        .fallback_service(serve_dir)
        .layer(cors)
        .with_state(shared_state);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8000")
        .await
        .expect("Failed to bind port 8000");

    tracing::info!("🦀 Server Core Rust berjalan di http://0.0.0.0:8000");

    axum::serve(listener, app).await.unwrap();
}
