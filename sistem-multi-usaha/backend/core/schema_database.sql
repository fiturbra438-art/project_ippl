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

-- Fungsi A: Validasi Ketersediaan Stok Sebelum Transaksi
CREATE OR REPLACE FUNCTION fn_cek_ketersediaan_stok(
    p_unit_id INT,
    p_product_id INT,
    p_qty INT
) RETURNS BOOLEAN AS $$
DECLARE
    v_stok_tersedia INT;
BEGIN
    SELECT qty INTO v_stok_tersedia 
    FROM inventories 
    WHERE unit_id = p_unit_id AND product_id = p_product_id;

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

-- PROSEDUR 1: CHECKOUT KASIR LENGKAP (Memanggil fn_cek_ketersediaan_stok, trigger trg_kurangi_stok, update shift, & catat audit)
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
BEGIN
    -- 1. Validasi Keberadaan Unit
    SELECT has_pos INTO v_unit_ada FROM business_units WHERE id = p_unit_id;
    IF v_unit_ada IS NULL THEN
        p_status_out := 'error';
        p_pesan_out := 'Unit usaha tidak ditemukan!';
        RETURN;
    END IF;

    -- 2. Validasi Ketersediaan Stok Menggunakan FUNCTION fn_cek_ketersediaan_stok
    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_prod_id := (item->>'product_id')::INT;
        v_qty := (item->>'qty')::INT;
        
        IF NOT fn_cek_ketersediaan_stok(p_unit_id, v_prod_id, v_qty) THEN
            p_status_out := 'error';
            p_pesan_out := 'Gagal: Stok untuk produk ID #' || v_prod_id || ' tidak mencukupi!';
            RETURN;
        END IF;
    END LOOP;

    -- 3. Hitung Total Pembelian via FUNCTION fn_hitung_total_belanja
    p_total_bayar := fn_hitung_total_belanja(p_items);

    -- 4. Buat Master Transaksi (Memicu TRIGGER trg_update_omzet_unit)
    INSERT INTO transactions (unit_id, kasir_id, tanggal, total, metode_bayar, status, created_at)
    VALUES (p_unit_id, p_kasir_id, now(), p_total_bayar, p_metode_bayar, 'selesai', now())
    RETURNING id INTO p_trx_id;

    -- 5. Masukkan Detail Item (Otomatis Memicu TRIGGER trg_kurangi_stok_inventaris)
    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_prod_id := (item->>'product_id')::INT;
        v_qty := (item->>'qty')::INT;
        v_harga := (item->>'harga_satuan')::NUMERIC;
        v_subtotal := v_harga * v_qty;

        INSERT INTO transaction_items (trx_id, product_id, qty, harga_satuan, subtotal, created_at)
        VALUES (p_trx_id, v_prod_id, v_qty, v_harga, v_subtotal, now());
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
