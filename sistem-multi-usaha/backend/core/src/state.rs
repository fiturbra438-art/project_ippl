use sqlx::PgPool;

pub struct AppState {
    pub db: PgPool,
    pub jwt_secret: String,
    pub ai_service_url: Option<String>,
    pub http: reqwest::Client,
}

impl AppState {
    pub async fn new(pool: PgPool) -> Self {
        // Jangan membuat akun demo/backdoor otomatis di lingkungan mana pun.
        // Akun owner harus dibuat melalui proses registrasi yang tersimpan di DB.

        // 1. Tambahkan kolom owner_id pada tabel users jika belum ada (multi-tenant support)
        let _ = sqlx::query("ALTER TABLE users ADD COLUMN IF NOT EXISTS owner_id INT REFERENCES users(id) ON DELETE CASCADE")
            .execute(&pool)
            .await;

        // 1b. Tambahkan kolom dynamic OTP dan masa kedaluwarsa pada tabel users
        let _ = sqlx::query("ALTER TABLE users ADD COLUMN IF NOT EXISTS otp_code VARCHAR(10)")
            .execute(&pool)
            .await;
        let _ = sqlx::query("ALTER TABLE users ADD COLUMN IF NOT EXISTS otp_expires_at TIMESTAMP")
            .execute(&pool)
            .await;
        let _ = sqlx::query(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS otp_attempts INT NOT NULL DEFAULT 0",
        )
        .execute(&pool)
        .await;

        // 1c. Migrasi skema kasir fleksibel (Rental, Jasa, Custom Note & Duration) pada tabel transactions & transaction_items
        let _ = sqlx::query(
            "ALTER TABLE transactions ADD COLUMN IF NOT EXISTS customer_name VARCHAR(150)",
        )
        .execute(&pool)
        .await;
        let _ = sqlx::query("ALTER TABLE transactions ADD COLUMN IF NOT EXISTS notes TEXT")
            .execute(&pool)
            .await;
        let _ = sqlx::query("ALTER TABLE transactions ADD COLUMN IF NOT EXISTS operation_mode VARCHAR(30) DEFAULT 'fleksibel'")
            .execute(&pool)
            .await;

        let _ = sqlx::query("ALTER TABLE transaction_items ALTER COLUMN product_id DROP NOT NULL")
            .execute(&pool)
            .await;
        let _ = sqlx::query(
            "ALTER TABLE transaction_items ADD COLUMN IF NOT EXISTS item_name VARCHAR(150)",
        )
        .execute(&pool)
        .await;
        let _ = sqlx::query("ALTER TABLE transaction_items ADD COLUMN IF NOT EXISTS item_type VARCHAR(30) DEFAULT 'barang'")
            .execute(&pool)
            .await;
        let _ = sqlx::query(
            "ALTER TABLE transaction_items ADD COLUMN IF NOT EXISTS rental_duration INT DEFAULT 1",
        )
        .execute(&pool)
        .await;
        let _ = sqlx::query("ALTER TABLE transaction_items ADD COLUMN IF NOT EXISTS duration_unit VARCHAR(20) DEFAULT 'jam'")
            .execute(&pool)
            .await;
        let _ = sqlx::query("ALTER TABLE transaction_items ADD COLUMN IF NOT EXISTS notes TEXT")
            .execute(&pool)
            .await;
        let _ = sqlx::query("ALTER TABLE transaction_items ADD COLUMN IF NOT EXISTS diskon NUMERIC(14,2) NOT NULL DEFAULT 0")
            .execute(&pool)
            .await;

        // 1d. Tabel Lifecycle Rental & Jasa (Active Orders, Status Pengerjaan & Pengembalian Sewa)
        let _ = sqlx::query(
            "CREATE TABLE IF NOT EXISTS rental_service_orders (
                id SERIAL PRIMARY KEY,
                trx_id INT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
                unit_id INT NOT NULL REFERENCES business_units(id) ON DELETE CASCADE,
                product_id INT REFERENCES products(id) ON DELETE SET NULL,
                item_name VARCHAR(150) NOT NULL,
                order_type VARCHAR(30) NOT NULL,
                customer_name VARCHAR(150),
                start_time TIMESTAMP NOT NULL DEFAULT now(),
                expected_end_time TIMESTAMP NOT NULL,
                actual_end_time TIMESTAMP,
                duration INT NOT NULL DEFAULT 1,
                duration_unit VARCHAR(20) NOT NULL DEFAULT 'jam',
                qty INT NOT NULL DEFAULT 1,
                status VARCHAR(30) NOT NULL,
                assigned_staff VARCHAR(100),
                deposit_amount NUMERIC(14,2) DEFAULT 0,
                penalty_fee NUMERIC(14,2) DEFAULT 0,
                notes TEXT,
                created_at TIMESTAMP NOT NULL DEFAULT now()
            )",
        )
        .execute(&pool)
        .await;

        let _ = sqlx::query("CREATE INDEX IF NOT EXISTS ix_rental_service_unit_status ON rental_service_orders(unit_id, status)")
            .execute(&pool)
            .await;
        let _ = sqlx::query("CREATE INDEX IF NOT EXISTS ix_rental_service_product_active ON rental_service_orders(product_id, status)")
            .execute(&pool)
            .await;
        let _ = sqlx::query(
            "ALTER TABLE rental_service_orders ADD COLUMN IF NOT EXISTS qty INT NOT NULL DEFAULT 1",
        )
        .execute(&pool)
        .await;

        // 1e. Status & waktu terima untuk mutasi transfer stok
        let _ = sqlx::query("ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'diterima'")
            .execute(&pool)
            .await;
        let _ = sqlx::query(
            "ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS waktu_terima TIMESTAMP",
        )
        .execute(&pool)
        .await;
        let _ = sqlx::query(
            "ALTER TABLE inventories ADD COLUMN IF NOT EXISTS reserved_qty INT NOT NULL DEFAULT 0",
        )
        .execute(&pool)
        .await;
        let _ = sqlx::query("ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS diminta_oleh INT REFERENCES users(id) ON DELETE SET NULL")
            .execute(&pool)
            .await;
        let _ = sqlx::query("ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS disetujui_oleh INT REFERENCES users(id) ON DELETE SET NULL")
            .execute(&pool)
            .await;
        let _ = sqlx::query(
            "ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS waktu_persetujuan TIMESTAMP",
        )
        .execute(&pool)
        .await;
        let _ = sqlx::query("ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS dikirim_oleh INT REFERENCES users(id) ON DELETE SET NULL")
            .execute(&pool)
            .await;
        let _ = sqlx::query(
            "ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS waktu_pengiriman TIMESTAMP",
        )
        .execute(&pool)
        .await;
        let _ = sqlx::query("ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS diterima_oleh INT REFERENCES users(id) ON DELETE SET NULL")
            .execute(&pool)
            .await;
        let _ = sqlx::query("ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS ditolak_oleh INT REFERENCES users(id) ON DELETE SET NULL")
            .execute(&pool)
            .await;
        let _ = sqlx::query(
            "ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS waktu_penolakan TIMESTAMP",
        )
        .execute(&pool)
        .await;
        let _ = sqlx::query(
            "ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS alasan_penolakan TEXT",
        )
        .execute(&pool)
        .await;
        let _ = sqlx::query("ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS dibatalkan_oleh INT REFERENCES users(id) ON DELETE SET NULL")
            .execute(&pool)
            .await;
        let _ = sqlx::query(
            "ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS waktu_pembatalan TIMESTAMP",
        )
        .execute(&pool)
        .await;

        // 1f. Kolom periode_omzet dan sinkronisasi casing kategori_portofolio di business_units
        let _ = sqlx::query("ALTER TABLE business_units ADD COLUMN IF NOT EXISTS periode_omzet VARCHAR(7) NOT NULL DEFAULT to_char(CURRENT_DATE, 'YYYY-MM')")
            .execute(&pool)
            .await;
        let _ = sqlx::query(
            "UPDATE business_units SET kategori_portofolio = CASE LOWER(kategori_portofolio)
                WHEN 'star' THEN 'Star'
                WHEN 'cash_cow' THEN 'Cash Cow'
                WHEN 'cash cow' THEN 'Cash Cow'
                WHEN 'question_mark' THEN 'Question Mark'
                WHEN 'question mark' THEN 'Question Mark'
                WHEN 'dog' THEN 'Dog'
                ELSE COALESCE(kategori_portofolio, 'Star')
            END",
        )
        .execute(&pool)
        .await;

        // Reset omzet bulanan jika periode_omzet berbeda dengan bulan berjalan
        let _ = sqlx::query(
            "UPDATE business_units
             SET pendapatan_bulan_ini = 0,
                 pengeluaran_bulan_ini = 0,
                 periode_omzet = to_char(CURRENT_DATE, 'YYYY-MM')
             WHERE COALESCE(periode_omzet, '') <> to_char(CURRENT_DATE, 'YYYY-MM')",
        )
        .execute(&pool)
        .await;

        sqlx::query(
            "CREATE TABLE IF NOT EXISTS transaction_refunds (
                id SERIAL PRIMARY KEY,
                transaction_id INT NOT NULL REFERENCES transactions(id) ON DELETE RESTRICT,
                owner_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                unit_id INT NOT NULL REFERENCES business_units(id) ON DELETE CASCADE,
                jenis VARCHAR(20) NOT NULL CHECK (jenis IN ('refund', 'void')),
                status VARCHAR(20) NOT NULL DEFAULT 'selesai',
                alasan TEXT NOT NULL,
                jumlah NUMERIC(14,2) NOT NULL CHECK (jumlah > 0),
                aktor_id INT REFERENCES users(id) ON DELETE SET NULL,
                aktor VARCHAR(150) NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT now()
            )",
        )
        .execute(&pool)
        .await
        .expect("Gagal memigrasikan tabel transaction_refunds");
        sqlx::query(
            "CREATE INDEX IF NOT EXISTS ix_transaction_refunds_transaction
             ON transaction_refunds(transaction_id, created_at)",
        )
        .execute(&pool)
        .await
        .expect("Gagal membuat index transaction_refunds");
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS transaction_refund_items (
                id SERIAL PRIMARY KEY,
                refund_id INT NOT NULL REFERENCES transaction_refunds(id) ON DELETE RESTRICT,
                transaction_item_id INT NOT NULL REFERENCES transaction_items(id) ON DELETE RESTRICT,
                product_id INT REFERENCES products(id) ON DELETE SET NULL,
                item_name VARCHAR(150) NOT NULL,
                item_type VARCHAR(30) NOT NULL,
                qty INT NOT NULL CHECK (qty > 0),
                jumlah NUMERIC(14,2) NOT NULL CHECK (jumlah > 0),
                UNIQUE (refund_id, transaction_item_id)
            )",
        )
        .execute(&pool)
        .await
        .expect("Gagal memigrasikan tabel transaction_refund_items");
        sqlx::query(
            "CREATE INDEX IF NOT EXISTS ix_transaction_refund_items_source
             ON transaction_refund_items(transaction_item_id)",
        )
        .execute(&pool)
        .await
        .expect("Gagal membuat index transaction_refund_items");

        // Perbarui trigger fungsi omzet agar otomatis me-reset di pergantian bulan
        let _ = sqlx::query(
            "CREATE OR REPLACE FUNCTION trg_fn_update_omzet_unit() 
            RETURNS TRIGGER AS $$
            DECLARE
                v_periode_trx VARCHAR(7);
            BEGIN
                IF NEW.status = 'selesai' THEN
                    v_periode_trx := to_char(COALESCE(NEW.tanggal, now()), 'YYYY-MM');
                    UPDATE business_units 
                    SET 
                        pendapatan_bulan_ini = CASE 
                            WHEN COALESCE(periode_omzet, '') = v_periode_trx THEN COALESCE(pendapatan_bulan_ini, 0) + NEW.total
                            ELSE NEW.total
                        END,
                        pengeluaran_bulan_ini = CASE 
                            WHEN COALESCE(periode_omzet, '') = v_periode_trx THEN COALESCE(pengeluaran_bulan_ini, 0)
                            ELSE 0
                        END,
                        periode_omzet = v_periode_trx
                    WHERE id = NEW.unit_id;
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;"
        )
        .execute(&pool)
        .await;

        let jwt_secret = std::env::var("JWT_SECRET")
            .expect("JWT_SECRET wajib diatur dan tidak boleh memakai secret default");

        let ai_service_url = std::env::var("AI_SERVICE_URL")
            .ok()
            .map(|value| value.trim().trim_end_matches('/').to_string())
            .filter(|value| !value.is_empty());

        let http = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(20))
            .build()
            .unwrap_or_else(|_| reqwest::Client::new());

        Self {
            db: pool,
            jwt_secret,
            ai_service_url,
            http,
        }
    }
}
