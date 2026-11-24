use axum::{
    body::{to_bytes, Body},
    extract::{Request, State},
    http::{header, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
    Json,
};
use std::sync::Arc;

use crate::schemas::ApiResponse;
use crate::state::AppState;

const MAX_AI_BODY_BYTES: usize = 16 * 1024 * 1024;

pub async fn forward_ai_request(
    State(state): State<Arc<AppState>>,
    request: Request,
    next: Next,
) -> Response {
    let Some(base_url) = state.ai_service_url.as_deref() else {
        return next.run(request).await;
    };

    if !request.uri().path().starts_with("/api/ai/") && !request.uri().path().starts_with("/ai/") {
        return next.run(request).await;
    }
    let method = request.method().clone();
    let path_and_query = request
        .uri()
        .path_and_query()
        .map(|value| value.as_str().to_string())
        .unwrap_or_else(|| request.uri().path().to_string());
    let headers = request.headers().clone();
    let (_, body) = request.into_parts();

    let body_bytes = match to_bytes(body, MAX_AI_BODY_BYTES).await {
        Ok(bytes) => bytes,
        Err(_) => {
            return ai_error(
                StatusCode::PAYLOAD_TOO_LARGE,
                "Permintaan AI melebihi batas ukuran yang diizinkan.",
            )
        }
    };

    let url = format!("{}{}", base_url.trim_end_matches('/'), path_and_query);
    let reqwest_method =
        reqwest::Method::from_bytes(method.as_str().as_bytes()).unwrap_or(reqwest::Method::GET);

    let mut builder = state.http.request(reqwest_method, url);
    if let Some(auth) = headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
    {
        builder = builder.header(header::AUTHORIZATION, auth);
    }
    if let Some(platform) = headers
        .get("x-client-platform")
        .and_then(|value| value.to_str().ok())
    {
        builder = builder.header("x-client-platform", platform);
    }
    if !body_bytes.is_empty() {
        builder = builder
            .header(header::CONTENT_TYPE, "application/json")
            .body(body_bytes.clone());
    }
    match builder.send().await {
        Ok(response) => {
            let status =
                StatusCode::from_u16(response.status().as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);
            let content_type = response.headers().get(header::CONTENT_TYPE).cloned();

            match response.bytes().await {
                Ok(bytes) => {
                    let mut proxied = Response::new(Body::from(bytes));
                    *proxied.status_mut() = status;
                    if let Some(content_type) = content_type {
                        proxied
                            .headers_mut()
                            .insert(header::CONTENT_TYPE, content_type);
                    }
                    proxied
                }
                Err(err) => {
                    tracing::warn!("Gagal membaca respons AI service: {}", err);
                    ai_error(
                        StatusCode::BAD_GATEWAY,
                        "Respons AI service tidak dapat dibaca.",
                    )
                }
            }
        }
        Err(err) => {
            tracing::warn!("AI service tidak dapat dijangkau: {}", err);
            ai_error(StatusCode::BAD_GATEWAY, "AI service tidak dapat dijangkau.")
        }
    }
}
pub fn ai_unavailable(message: &str) -> Response {
    ai_error(StatusCode::SERVICE_UNAVAILABLE, message)
}
fn ai_error(status: StatusCode, message: &str) -> Response {
    (
        status,
        Json(ApiResponse::<serde_json::Value> {
            status: "error".to_string(),
            message: message.to_string(),
            data: None,
        }),
    )
        .into_response()
}
