use lettre::message::header::ContentType;
use lettre::transport::smtp::authentication::Credentials;
use lettre::{AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor};
use rand::Rng;
use serde_json::json;

pub fn generate_dynamic_otp() -> String {
    let mut rng = rand::thread_rng();
    let code: u32 = rng.gen_range(100_000..=999_999);
    code.to_string()
}

pub async fn send_otp_email(recipient_email: &str, recipient_name: &str, otp_code: &str) -> Result<(), String> {
    let email_body = format!(
        r#"Halo {},

Kode One-Time Password (OTP) Anda untuk masuk ke Sistem Manajemen Multi-Usaha adalah:

    {}

Kode ini bersifat rahasia dan berlaku selama 5 menit.
Jangan berikan kode ini kepada siapa pun termasuk staf atau pihak yang mengaku sebagai admin.

Salam,
Tim Keamanan Multi-Usaha
"#,
        recipient_name, otp_code
    );

    // 1. Cek apakah ada RESEND_API_KEY
    let resend_api_key = std::env::var("RESEND_API_KEY").unwrap_or_default();
    if !resend_api_key.trim().is_empty() {
        let from_email = std::env::var("RESEND_FROM").unwrap_or_else(|_| "MultiUsaha <onboarding@resend.dev>".to_string());
        let client = reqwest::Client::new();
        let payload = json!({
            "from": from_email,
            "to": [recipient_email],
            "subject": format!("Kode OTP Masuk Multi-Usaha: {}", otp_code),
            "text": email_body,
        });

        let res = client
            .post("https://api.resend.com/emails")
            .bearer_auth(resend_api_key.trim())
            .json(&payload)
            .send()
            .await
            .map_err(|e| format!("Request Resend gagal: {}", e))?;

        if res.status().is_success() {
            tracing::info!("✉️ [Resend API] Email OTP berhasil dikirim ke {}", recipient_email);
            return Ok(());
        } else {
            let err_text = res.text().await.unwrap_or_default();
            tracing::error!("❌ [Resend API] Gagal kirim email: {}", err_text);
            return Err(format!("Resend API error: {}", err_text));
        }
    }

    // 2. Fallback SMTP
    let smtp_host = std::env::var("SMTP_HOST").unwrap_or_default();
    let smtp_port: u16 = std::env::var("SMTP_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(587);
    let smtp_user = std::env::var("SMTP_USER").unwrap_or_default();
    let smtp_pass = std::env::var("SMTP_PASSWORD").unwrap_or_default();
    let smtp_from = std::env::var("SMTP_FROM").unwrap_or_else(|_| "MultiUsaha <no-reply@multi-usaha.com>".to_string());

    if !smtp_host.trim().is_empty() && !smtp_user.trim().is_empty() {
        let email = Message::builder()
            .from(smtp_from.parse().map_err(|e| format!("Header FROM tidak valid: {}", e))?)
            .to(format!("{} <{}>", recipient_name, recipient_email)
                .parse()
                .map_err(|e| format!("Header TO tidak valid: {}", e))?)
            .subject("Kode OTP Masuk Multi-Usaha")
            .header(ContentType::TEXT_PLAIN)
            .body(email_body)
            .map_err(|e| format!("Gagal menyusun pesan email: {}", e))?;

        let creds = Credentials::new(smtp_user, smtp_pass);
        let mailer: AsyncSmtpTransport<Tokio1Executor> = if smtp_port == 465 {
            AsyncSmtpTransport::<Tokio1Executor>::relay(&smtp_host)
                .map_err(|e| format!("Relay SSL gagal: {}", e))?
                .credentials(creds)
                .build()
        } else {
            AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(&smtp_host)
                .map_err(|e| format!("Relay STARTTLS gagal: {}", e))?
                .port(smtp_port)
                .credentials(creds)
                .build()
        };

        mailer.send(email).await.map_err(|e| format!("Gagal mengirim email OTP: {}", e))?;
        tracing::info!("✉️ [SMTP] Email OTP berhasil terkirim ke {}", recipient_email);
        return Ok(());
    }

    // 3. Fallback Log Terminal jika tidak ada API Key atau SMTP
    tracing::warn!("⚠️ Belum ada RESEND_API_KEY atau SMTP. Kode OTP untuk {} ({}) adalah: {}", recipient_name, recipient_email, otp_code);
    Ok(())
}
