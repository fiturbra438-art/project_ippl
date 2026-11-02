-- ============================================================================
-- SQL DDL: VIEW, FUNCTION, TRIGGER & STORED PROCEDURE
-- Pola Desain: Prosedur Utama memanggil View, Function, dan Trigger otomatis
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. VIEW (Ringkasan Konsolidasi & Monitoring Keuangan)
-- ----------------------------------------------------------------------------

-- View A: Ringkasan Performa Cabang & Pendapatan Real-time
CREATE OR REPLACE VIEW view_ringkasan_unit_usaha AS
SELECT 
    u.id AS unit_id,
    u.owner_id,
    u.nama AS nama_unit,
    u.jenis_usaha,
    u.lokasi,
    u.kategori_portofolio,
    u.has_pos,
    u.status,
    COALESCE(SUM(CASE WHEN t.status = 'selesai' THEN t.total ELSE 0 END), 0) AS total_omzet,
    COUNT(DISTINCT t.id) AS total_transaksi,
    COUNT(DISTINCT i.product_id) AS total_item_terdaftar,
    COALESCE(SUM(CASE WHEN i.qty <= i.min_stock THEN 1 ELSE 0 END), 0) AS jumlah_stok_kritis
FROM business_units u
LEFT JOIN transactions t ON u.id = t.unit_id
LEFT JOIN inventories i ON u.id = i.unit_id
GROUP BY u.id, u.owner_id, u.nama, u.jenis_usaha, u.lokasi, u.kategori_portofolio, u.has_pos, u.status;

-- View B: Produk Kritis & Perlu Restok
CREATE OR REPLACE VIEW view_produk_stok_kritis AS
SELECT 
    i.id AS inventory_id,
    i.unit_id,
    u.nama AS nama_unit,
    p.id AS product_id,
    p.nama AS nama_produk,
    p.sku,
    p.harga_jual,
    p.harga_beli,
    i.qty AS stok_saat_ini,
    i.min_stock AS batas_minimum,
    (i.min_stock - i.qty) AS kebutuhan_restok
FROM inventories i
JOIN products p ON i.product_id = p.id
JOIN business_units u ON i.unit_id = u.id
WHERE i.qty <= i.min_stock;


-- ----------------------------------------------------------------------------
-- 2. FUNCTION (Fungsi Perhitungan, Validasi & Logic)
-- ----------------------------------------------------------------------------

-- Fungsi A: Validasi Ketersediaan Stok Sebelum Transaksi (Dengan Row-Level Pessimistic Lock FOR UPDATE)
CREATE OR REPLACE FUNCTION fn_cek_ketersediaan_stok(
    p_unit_id INT,
    p_product_id INT,
    p_qty INT
) RETURNS BOOLEAN AS $$
DECLARE
    v_stok_tersedia INT;
BEGIN
    -- Menggunakan FOR UPDATE untuk mencegah Race Condition / Concurrency Conflict
    SELECT qty INTO v_stok_tersedia 
    FROM inventories 
    WHERE unit_id = p_unit_id AND product_id = p_product_id
    FOR UPDATE;

    IF v_stok_tersedia IS NULL OR v_stok_tersedia < p_qty THEN
        RETURN FALSE;
    END IF;
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Fungsi B: Hitung Total Keranjang Belanja dari JSON Item
CREATE OR REPLACE FUNCTION fn_hitung_total_belanja(
    p_items JSONB
) RETURNS NUMERIC(14,2) AS $$
DECLARE
    item JSONB;
    v_total NUMERIC(14,2) := 0;
    v_subtotal NUMERIC(14,2);
BEGIN
    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_subtotal := (item->>'harga_satuan')::NUMERIC * (item->>'qty')::INT;
        v_total := v_total + v_subtotal;
    END LOOP;
    RETURN v_total;
END;
$$ LANGUAGE plpgsql;


-- ----------------------------------------------------------------------------
-- 3. TRIGGER & TRIGGER FUNCTION (Otomatisasi Potong Stok & Audit)
-- ----------------------------------------------------------------------------

-- Trigger Function A: Otomatis Potong Stok saat Transaksi Baru Ditambahkan
CREATE OR REPLACE FUNCTION trg_fn_kurangi_stok_inventaris() 
RETURNS TRIGGER AS $$
DECLARE
    v_unit_id INT;
    v_inv_id INT;
BEGIN
    -- Jika product_id NULL atau 0 (item non-stok / jasa / rental / ad-hoc), lewati pengurangan inventori fisik
    IF NEW.product_id IS NULL OR NEW.product_id <= 0 THEN
        RETURN NEW;
    END IF;

    SELECT unit_id INTO v_unit_id FROM transactions WHERE id = NEW.trx_id;

    -- Kurangi kuantitas stok di tabel inventories
    UPDATE inventories 
    SET qty = qty - NEW.qty
    WHERE product_id = NEW.product_id AND unit_id = v_unit_id
    RETURNING id INTO v_inv_id;

    -- Catat riwayat pergerakan stok (tipe = 'keluar' sesuai check constraint ck_movement_unit_sesuai_tipe)
    IF v_inv_id IS NOT NULL THEN
        INSERT INTO stock_movements (inventory_id, tipe, qty, tanggal, unit_asal_id, unit_tujuan_id, created_at)
        VALUES (v_inv_id, 'keluar', NEW.qty, now(), v_unit_id, NULL, now());
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_kurangi_stok_inventaris ON transaction_items;
CREATE TRIGGER trg_kurangi_stok_inventaris
AFTER INSERT ON transaction_items
FOR EACH ROW
EXECUTE FUNCTION trg_fn_kurangi_stok_inventaris();

-- Trigger Function B: Otomatis Update Omzet Unit Usaha saat Transaksi Berhasil
CREATE OR REPLACE FUNCTION trg_fn_update_omzet_unit() 
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'selesai' THEN
        UPDATE business_units 
        SET pendapatan_bulan_ini = COALESCE(pendapatan_bulan_ini, 0) + NEW.total
        WHERE id = NEW.unit_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_omzet_unit ON transactions;
CREATE TRIGGER trg_update_omzet_unit
AFTER INSERT ON transactions
FOR EACH ROW
EXECUTE FUNCTION trg_fn_update_omzet_unit();


-- ----------------------------------------------------------------------------
-- 4. STORED PROCEDURES (TITIK PANGGIL TUNGGAL DARI APLIKASI)
-- Aplikasi Backend Rust HANYA PERLU MEMANGGIL PROCEDURE INI ("CALL sp_...")
-- ----------------------------------------------------------------------------

-- PROSEDUR 1: CHECKOUT KASIR FLEKSIBEL (Mendukung Retail, Sewa/Rental, Jasa, & Ad-hoc Kustom)
CREATE OR REPLACE PROCEDURE sp_proses_checkout_kasir(
    IN p_unit_id INT,
    IN p_kasir_id INT,
    IN p_metode_bayar VARCHAR,
    IN p_items JSONB,
    OUT p_trx_id INT,
    OUT p_total_bayar NUMERIC(14,2),
    OUT p_status_out VARCHAR,
    OUT p_pesan_out TEXT
)
AS $$
DECLARE
    item JSONB;
    v_prod_id INT;
    v_qty INT;
    v_harga NUMERIC(14,2);
    v_subtotal NUMERIC(14,2);
    v_unit_ada BOOLEAN;
    v_is_tunai BOOLEAN;
    v_tipe VARCHAR(30);
    v_custom_nama VARCHAR(150);
    v_durasi INT;
    v_unit_durasi VARCHAR(20);
    v_catatan TEXT;
BEGIN
    -- 1. Validasi Keberadaan Unit
    SELECT has_pos INTO v_unit_ada FROM business_units WHERE id = p_unit_id;
    IF v_unit_ada IS NULL THEN
        p_status_out := 'error';
        p_pesan_out := 'Unit usaha tidak ditemukan!';
        RETURN;
    END IF;

    -- 2. Validasi Ketersediaan Stok (Hanya untuk item barang fisik yang memiliki product_id valid > 0)
    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_prod_id := COALESCE((item->>'product_id')::INT, 0);
        v_qty := COALESCE((item->>'qty')::INT, 1);
        v_tipe := COALESCE(item->>'tipe', 'barang');
        
        -- Hanya cek stok jika item bertipe 'barang' dan memiliki product_id fisik
        IF v_prod_id > 0 AND LOWER(v_tipe) = 'barang' THEN
            IF NOT fn_cek_ketersediaan_stok(p_unit_id, v_prod_id, v_qty) THEN
                p_status_out := 'error';
                p_pesan_out := 'Gagal: Stok untuk produk ID #' || v_prod_id || ' tidak mencukupi!';
                RETURN;
            END IF;
        END IF;
    END LOOP;

    -- 3. Hitung Total Pembelian via FUNCTION fn_hitung_total_belanja
    p_total_bayar := fn_hitung_total_belanja(p_items);

    -- 4. Buat Master Transaksi (Memicu TRIGGER trg_update_omzet_unit)
    INSERT INTO transactions (unit_id, kasir_id, tanggal, total, metode_bayar, status, created_at)
    VALUES (p_unit_id, p_kasir_id, now(), p_total_bayar, p_metode_bayar, 'selesai', now())
    RETURNING id INTO p_trx_id;

    -- 5. Masukkan Detail Item (Mendukung Produk Fisik, Rental, Jasa, atau Custom)
    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_prod_id := NULLIF(COALESCE((item->>'product_id')::INT, 0), 0);
        v_qty := COALESCE((item->>'qty')::INT, 1);
        v_harga := (item->>'harga_satuan')::NUMERIC;
        v_subtotal := v_harga * v_qty;
        v_tipe := COALESCE(item->>'tipe', 'barang');
        v_custom_nama := item->>'nama';
        v_durasi := COALESCE((item->>'durasi')::INT, 1);
        v_unit_durasi := item->>'unit_durasi';
        v_catatan := item->>'catatan';

        INSERT INTO transaction_items (
            trx_id, product_id, item_name, item_type, qty, harga_satuan, subtotal, rental_duration, duration_unit, notes, created_at
        ) VALUES (
            p_trx_id, 
            v_prod_id, 
            v_custom_nama, 
            v_tipe, 
            v_qty, 
            v_harga, 
            v_subtotal, 
            v_durasi, 
            v_unit_durasi, 
            v_catatan, 
            now()
        );

        -- Otomatis buat entri pelacakan aktif jika item adalah Rental atau Jasa
        IF LOWER(v_tipe) = 'rental' THEN
            INSERT INTO rental_service_orders (
                trx_id, unit_id, product_id, item_name, order_type, customer_name,
                start_time, expected_end_time, duration, duration_unit, status, notes, created_at
            ) VALUES (
                p_trx_id,
                p_unit_id,
                v_prod_id,
                COALESCE(v_custom_nama, 'Barang Sewa'),
                'rental',
                (SELECT customer_name FROM transactions WHERE id = p_trx_id),
                now(),
                CASE 
                    WHEN LOWER(v_unit_durasi) = 'hari' THEN now() + (v_durasi || ' days')::INTERVAL
                    ELSE now() + (v_durasi || ' hours')::INTERVAL
                END,
                v_durasi,
                COALESCE(v_unit_durasi, 'jam'),
                'active',
                v_catatan,
                now()
            );
        ELSIF LOWER(v_tipe) = 'jasa' THEN
            INSERT INTO rental_service_orders (
                trx_id, unit_id, product_id, item_name, order_type, customer_name,
                start_time, expected_end_time, duration, duration_unit, status, notes, created_at
            ) VALUES (
                p_trx_id,
                p_unit_id,
                v_prod_id,
                COALESCE(v_custom_nama, 'Layanan Jasa'),
                'service',
                (SELECT customer_name FROM transactions WHERE id = p_trx_id),
                now(),
                now() + (v_durasi || ' hours')::INTERVAL,
                v_durasi,
                COALESCE(v_unit_durasi, 'jam'),
                'in_progress',
                v_catatan,
                now()
            );
        END IF;
    END LOOP;

    -- 6. Update Shift Kasir Aktif
    v_is_tunai := (LOWER(p_metode_bayar) LIKE '%tunai%' OR LOWER(p_metode_bayar) LIKE '%cash%');
    UPDATE cashier_shifts
    SET 
        total_penjualan_tunai = total_penjualan_tunai + CASE WHEN v_is_tunai THEN p_total_bayar ELSE 0 END,
        total_penjualan_non_tunai = total_penjualan_non_tunai + CASE WHEN NOT v_is_tunai THEN p_total_bayar ELSE 0 END,
        total_transaksi = total_transaksi + 1
    WHERE unit_id = p_unit_id AND status = 'open';

    -- 7. Catat ke Audit Trail
    INSERT INTO audit_logs (owner_id, aktor, role, aksi, modul, target, detail, waktu)
    VALUES (
        (SELECT owner_id FROM business_units WHERE id = p_unit_id),
        (SELECT COALESCE(nama, 'Kasir') FROM users WHERE id = p_kasir_id),
        'kasir',
        'Checkout POS',
        'Kasir',
        'Unit #' || p_unit_id,
        'Transaksi #' || p_trx_id || ' sukses senilai Rp ' || p_total_bayar || ' via ' || p_metode_bayar,
        now()
    );

    p_status_out := 'success';
    p_pesan_out := 'Transaksi checkout kasir berhasil diselesaikan!';
END;
$$ LANGUAGE plpgsql;


-- PROSEDUR 2: BUKA SHIFT KASIR
CREATE OR REPLACE PROCEDURE sp_buka_shift_kasir(
    IN p_unit_id INT,
    IN p_kasir_id INT,
    IN p_nama_kasir VARCHAR,
    IN p_modal_awal NUMERIC(14,2),
    OUT p_shift_id INT,
    OUT p_status_out VARCHAR,
    OUT p_pesan_out TEXT
)
AS $$
BEGIN
    -- Pastikan tidak ada shift yang masih menggantung terbuka
    IF EXISTS (SELECT 1 FROM cashier_shifts WHERE unit_id = p_unit_id AND status = 'open') THEN
        p_status_out := 'error';
        p_pesan_out := 'Masih ada shift kasir yang terbuka pada unit ini. Tutup shift terlebih dahulu.';
        RETURN;
    END IF;

    INSERT INTO cashier_shifts (
        unit_id, kasir_id, nama_kasir, modal_awal, total_penjualan_tunai, total_penjualan_non_tunai, total_transaksi, waktu_buka, status
    ) VALUES (
        p_unit_id, p_kasir_id, p_nama_kasir, p_modal_awal, 0, 0, 0, now(), 'open'
    ) RETURNING id INTO p_shift_id;

    p_status_out := 'success';
    p_pesan_out := 'Shift kasir berhasil dibuka dengan modal awal Rp ' || p_modal_awal;
END;
$$ LANGUAGE plpgsql;


-- PROSEDUR 3: TUTUP SHIFT KASIR
CREATE OR REPLACE PROCEDURE sp_tutup_shift_kasir(
    IN p_shift_id INT,
    IN p_uang_fisik_laci NUMERIC(14,2),
    OUT p_selisih NUMERIC(14,2),
    OUT p_status_out VARCHAR,
    OUT p_pesan_out TEXT
)
AS $$
DECLARE
    v_shift RECORD;
    v_total_seharusnya NUMERIC(14,2);
BEGIN
    SELECT * INTO v_shift FROM cashier_shifts WHERE id = p_shift_id AND status = 'open';
    IF NOT FOUND THEN
        p_status_out := 'error';
        p_pesan_out := 'Shift kasir tidak ditemukan atau sudah ditutup!';
        RETURN;
    END IF;

    v_total_seharusnya := v_shift.modal_awal + v_shift.total_penjualan_tunai;
    p_selisih := p_uang_fisik_laci - v_total_seharusnya;

    UPDATE cashier_shifts
    SET waktu_tutup = now(), status = 'closed'
    WHERE id = p_shift_id;

    p_status_out := 'success';
    p_pesan_out := 'Shift kasir berhasil ditutup. Total transaksi: ' || v_shift.total_transaksi || ', Selisih laci kas: Rp ' || p_selisih;
END;
$$ LANGUAGE plpgsql;


-- PROSEDUR 4: MUTASI / TRANSFER STOK ANTAR CABANG
CREATE OR REPLACE PROCEDURE sp_transfer_stok_antar_unit(
    IN p_unit_asal_id INT,
    IN p_unit_tujuan_id INT,
    IN p_product_id INT,
    IN p_qty INT,
    IN p_operator_id INT,
    OUT p_status_out VARCHAR,
    OUT p_pesan_out TEXT
)
AS $$
BEGIN
    -- Validasi stok asal via Function
    IF NOT fn_cek_ketersediaan_stok(p_unit_asal_id, p_product_id, p_qty) THEN
        p_status_out := 'error';
        p_pesan_out := 'Stok di unit asal tidak mencukupi untuk transfer!';
        RETURN;
    END IF;

    -- 1. Kurangi stok unit asal
    UPDATE inventories 
    SET qty = qty - p_qty
    WHERE unit_id = p_unit_asal_id AND product_id = p_product_id;

    -- 2. Tambah stok unit tujuan (Insert jika belum ada, Update jika sudah ada)
    INSERT INTO inventories (unit_id, product_id, qty, min_stock, created_at)
    VALUES (p_unit_tujuan_id, p_product_id, p_qty, 5, now())
    ON CONFLICT (unit_id, product_id)
    DO UPDATE SET qty = inventories.qty + p_qty;

    -- 3. Catat Riwayat Transfer (tipe = 'transfer' sesuai check constraint ck_movement_unit_sesuai_tipe)
    INSERT INTO stock_movements (inventory_id, tipe, qty, tanggal, unit_asal_id, unit_tujuan_id, dicatat_oleh, created_at)
    SELECT id, 'transfer', p_qty, now(), p_unit_asal_id, p_unit_tujuan_id, p_operator_id, now()
    FROM inventories
    WHERE unit_id = p_unit_asal_id AND product_id = p_product_id
    LIMIT 1;

    p_status_out := 'success';
    p_pesan_out := 'Transfer ' || p_qty || ' unit produk berhasil dipindahkan.';
END;
$$ LANGUAGE plpgsql;


-- ----------------------------------------------------------------------------
-- 5. TABEL LIFECYCLE ORDER RENTAL & JASA
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rental_service_orders (
    id SERIAL PRIMARY KEY,
    trx_id INT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    unit_id INT NOT NULL REFERENCES business_units(id) ON DELETE CASCADE,
    product_id INT REFERENCES products(id) ON DELETE SET NULL,
    item_name VARCHAR(150) NOT NULL,
    order_type VARCHAR(30) NOT NULL, -- 'rental', 'service'
    customer_name VARCHAR(150),
    start_time TIMESTAMP NOT NULL DEFAULT now(),
    expected_end_time TIMESTAMP NOT NULL,
    actual_end_time TIMESTAMP,
    duration INT NOT NULL DEFAULT 1,
    duration_unit VARCHAR(20) NOT NULL DEFAULT 'jam',
    status VARCHAR(30) NOT NULL, -- Rental: 'active', 'returned', 'overdue' | Jasa: 'queued', 'in_progress', 'ready', 'completed'
    assigned_staff VARCHAR(100),
    deposit_amount NUMERIC(14,2) DEFAULT 0,
    penalty_fee NUMERIC(14,2) DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_rental_service_unit_status ON rental_service_orders(unit_id, status);
CREATE INDEX IF NOT EXISTS ix_rental_service_product_active ON rental_service_orders(product_id, status);

-- ----------------------------------------------------------------------------
-- 6. SEED DATA DEFAULT (DATABASE SAMPLE DATA)
-- Hanya di-insert jika database masih kosong untuk keperluan uji coba awal
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_owner_id INT;
    v_unit_toko INT;
    v_unit_rental INT;
    v_unit_jasa INT;
    v_prod_kopi INT;
    v_prod_snack INT;
    v_prod_kamera INT;
    v_prod_ps5 INT;
    v_prod_cuci INT;
    v_prod_servis INT;
BEGIN
    -- Cek jika tabel users belum memiliki owner
    IF NOT EXISTS (SELECT 1 FROM users WHERE role = 'owner') THEN
        INSERT INTO users (nama, email, password_hash, role, aktif, nama_perusahaan, tier, kuota_unit_usaha, sisa_kuota_ai)
        VALUES (
            'Pemilik Usaha',
            'owner@multi-usaha.com',
            '$2b$12$e8Ym1oKq/150gJvhY1rYze750E6Z.7eQZ4N0R6jXzRzM4J3iFwYmi', -- password default jika diperlukan
            'owner',
            true,
            'PT Multi Niaga Nusantara',
            'pro',
            10,
            250
        ) RETURNING id INTO v_owner_id;

        -- 1. Cabang Minimart / Toko Retail
        INSERT INTO business_units (owner_id, nama, jenis_usaha, lokasi, kategori_portofolio, status, has_pos, pendapatan_bulan_ini, pengeluaran_bulan_ini, pertumbuhan_persen)
        VALUES (v_owner_id, 'Minimart Cabang Merdeka', 'Retail & Kelontong', 'Jl. Merdeka No. 10', 'star', true, true, 4500000.00, 1500000.00, 12.5)
        RETURNING id INTO v_unit_toko;

        -- 2. Cabang Rental / Penyewaan
        INSERT INTO business_units (owner_id, nama, jenis_usaha, lokasi, kategori_portofolio, status, has_pos, pendapatan_bulan_ini, pengeluaran_bulan_ini, pertumbuhan_persen)
        VALUES (v_owner_id, 'Multi Rental Studio & Game', 'Rental & Penyewaan', 'Jl. Sudirman No. 45', 'cash_cow', true, true, 6200000.00, 1800000.00, 8.4)
        RETURNING id INTO v_unit_rental;

        -- 3. Cabang Jasa & Servis
        INSERT INTO business_units (owner_id, nama, jenis_usaha, lokasi, kategori_portofolio, status, has_pos, pendapatan_bulan_ini, pengeluaran_bulan_ini, pertumbuhan_persen)
        VALUES (v_owner_id, 'QuickFix Servis & Laundry', 'Jasa & Reparasi', 'Jl. Pemuda No. 8', 'question_mark', true, true, 3100000.00, 950000.00, 15.2)
        RETURNING id INTO v_unit_jasa;

        -- Produk Retail
        INSERT INTO products (owner_id, sku, nama, kategori, harga_beli, harga_jual, satuan)
        VALUES (v_owner_id, 'RET-001', 'Kopi Arabika 250gr', 'Minuman', 25000.00, 45000.00, 'pcs')
        RETURNING id INTO v_prod_kopi;

        INSERT INTO products (owner_id, sku, nama, kategori, harga_beli, harga_jual, satuan)
        VALUES (v_owner_id, 'RET-002', 'Keripik Kentang Renyah', 'Makanan', 10000.00, 18000.00, 'pcs')
        RETURNING id INTO v_prod_snack;

        -- Produk Rental (Aset Sewa)
        INSERT INTO products (owner_id, sku, nama, kategori, harga_beli, harga_jual, satuan)
        VALUES (v_owner_id, 'RNT-001', 'Kamera Sony Alpha Mirrorless', 'Elektronik Rental', 8500000.00, 150000.00, 'hari')
        RETURNING id INTO v_prod_kamera;

        INSERT INTO products (owner_id, sku, nama, kategori, harga_beli, harga_jual, satuan)
        VALUES (v_owner_id, 'RNT-002', 'PlayStation 5 Console + 2 Stick', 'Rental Game', 9000000.00, 25000.00, 'jam')
        RETURNING id INTO v_prod_ps5;

        -- Produk Jasa
        INSERT INTO products (owner_id, sku, nama, kategori, harga_beli, harga_jual, satuan)
        VALUES (v_owner_id, 'JSA-001', 'Cuci & Deep Clean Sepatu', 'Perawatan', 5000.00, 35000.00, 'pasang')
        RETURNING id INTO v_prod_cuci;

        INSERT INTO products (owner_id, sku, nama, kategori, harga_beli, harga_jual, satuan)
        VALUES (v_owner_id, 'JSA-002', 'Servis AC & Cuci Freon', 'Jasa Servis', 20000.00, 85000.00, 'unit')
        RETURNING id INTO v_prod_servis;

        -- Masukkan ke Inventori Cabang Terkait
        INSERT INTO inventories (unit_id, product_id, qty, min_stock, lokasi_rak)
        VALUES 
            (v_unit_toko, v_prod_kopi, 45, 10, 'Rak Minuman A1'),
            (v_unit_toko, v_prod_snack, 60, 15, 'Rak Snack B2'),
            (v_unit_rental, v_prod_kamera, 3, 1, 'Lemari Khusus L1'),
            (v_unit_rental, v_prod_ps5, 4, 1, 'Meja Konsol K1'),
            (v_unit_jasa, v_prod_cuci, 999, 10, 'Area Cuci'),
            (v_unit_jasa, v_prod_servis, 999, 5, 'Area Teknisi');
    END IF;
END $$;
