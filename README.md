# Sistem Manajemen Multi-Usaha (Multi-Business Management System)

Aplikasi terintegrasi untuk mengelola berbagai cabang dan unit usaha (multi-tenant/multi-branch) dengan dukungan POS (Point of Sale), manajemen inventaris & pergudangan terpadu, analitik portofolio keuangan, serta fitur kecerdasan buatan (AI Assistant & Forecasting).

---

## 🏗 Arsitektur Sistem

Proyek ini dibangun menggunakan arsitektur monorepo modular:

```text
IPPL/
├── sistem-multi-usaha/
│   ├── backend/
│   │   ├── core/       # High-performance Core Backend (Rust - Axum, Tokio, SQLx)
│   │   └── ai/         # AI Microservice & Data Analytics (Python - FastAPI, SQLAlchemy)
│   └── frontend/       # Responsive Multiplatform UI (Flutter - Web, Desktop & Mobile)
```

### 1. **Core Backend (`backend/core`)**
- **Teknologi:** Rust (Axum, Tokio, SQLx, Tower-HTTP, Rust-Decimal, JWT, Bcrypt).
- **Fungsi Utama:**
  - Autentikasi Pengguna & Karyawan (RBAC & multi-tier: Free, Pro, Enterprise).
  - Manajemen Cabang / Unit Usaha multi-sektor (Retail, F&B, Jasa).
  - Manajemen Produk, Multi-gudang, Stok Opname, dan Transfer Antar-Gudang.
  - Modul POS (Point of Sale) lengkap dengan manajemen shift kasir (buka/tutup shift).
  - Transaksi otomatis dengan penanganan *concurrency/row-level lock* (`FOR UPDATE`) di level PostgreSQL.
  - Laporan keuangan, ringkasan dashboard, dan audit log aktivitas.
  - Serving langsung Flutter Web build sebagai fallback web app.

### 2. **AI & Analytics Service (`backend/ai`)**
- **Teknologi:** Python 3 (FastAPI, SQLAlchemy, Alembic, Pydantic).
- **Fungsi Utama:**
  - AI Assistant / Chatbot untuk wawasan operasional bisnis.
  - Prediksi penjualan dan peramalan kebutuhan stok (*Forecasting*).
  - Deteksi anomali penjualan dan analitik matriks performa portofolio bisnis.

### 3. **Frontend Client (`frontend`)**
- **Teknologi:** Flutter 3 (Provider pattern, Material 3, Responsive Layout).
- **Fungsi Utama:**
  - Tampilan responsif adaptif untuk Web/Desktop (sidebar-based) dan Mobile (drawer-based).
  - POS Cashier Interface dengan integrasi kalkulator bayar & struk.
  - Dashboard eksekutif multi-cabang (omzet, tren, perbandingan performa unit).
  - Modul Gudang: Permintaan stok, stok opname, dan approval transfer stok.
  - AI Business Hub: AI Chat Consultant, Demand Forecasting, dan Deteksi Anomali.

---

## 🛠 Prasyarat Sistem

Pastikan tools berikut sudah terinstal di sistem Anda:
- **Rust & Cargo** (v1.75+): [https://rustup.rs/](https://rustup.rs/)
- **Python** (v3.10+): [https://www.python.org/](https://www.python.org/)
- **Flutter SDK** (v3.22+): [https://flutter.dev/](https://flutter.dev/)
- **PostgreSQL Database** (v14+): [https://www.postgresql.org/](https://www.postgresql.org/)

---

## 🚀 Panduan Instalasi & Menjalankan

### 1. Persiapan Database PostgreSQL

1. Buat database dan user di PostgreSQL:
   ```bash
   sudo -u postgres psql
   ```
   ```sql
   CREATE DATABASE usaha_db;
   CREATE USER usaha_user WITH ENCRYPTED PASSWORD 'password_rahasia_anda';
   GRANT ALL PRIVILEGES ON DATABASE usaha_db TO usaha_user;
   \c usaha_db
   GRANT ALL ON SCHEMA public TO usaha_user;
   \q
   ```

2. Jalankan skema database lengkap (tabel, view, function, trigger, dan sample data):
   ```bash
   psql -U usaha_user -d usaha_db -h localhost -f sistem-multi-usaha/backend/core/schema_database.sql
   ```

---

### 2. Menjalankan Core Backend (Rust)

1. Masuk ke direktori `backend/core`:
   ```bash
   cd sistem-multi-usaha/backend/core
   ```

2. Buat berkas konfigurasi `.env`:
   ```env
   DATABASE_URL=postgresql://usaha_user:password_rahasia_anda@localhost:5432/usaha_db
   PORT=8000
   JWT_SECRET=super_secret_jwt_key_12345
   WEB_DIR=../../frontend/build/web
   ```

3. Jalankan server:
   ```bash
   cargo run
   ```
   Server Core Rust akan berjalan di `http://0.0.0.0:8000`.

---

### 3. Menjalankan AI Service (Python FastAPI)

1. Masuk ke direktori `backend/ai`:
   ```bash
   cd sistem-multi-usaha/backend/ai
   ```

2. Buat virtual environment dan pasang dependensi:
   ```bash
   python -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

3. Konfigurasi file `.env`:
   ```env
   DATABASE_URL=postgresql://usaha_user:password_rahasia_anda@localhost:5432/usaha_db
   PORT=8001
   ```

4. Jalankan migrasi Alembic (jika diperlukan) dan jalankan server:
   ```bash
   uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload
   ```
   Dokumentasi OpenAPI Swagger tersedia di `http://localhost:8001/docs`.

---

### 4. Menjalankan Frontend (Flutter)

1. Masuk ke direktori `frontend`:
   ```bash
   cd sistem-multi-usaha/frontend
   ```

2. Ambil semua dependensi package:
   ```bash
   flutter pub get
   ```

3. Jalankan aplikasi pada target pilihan Anda:
   - **Web (Chrome / Edge):**
     ```bash
     flutter run -d chrome
     ```
   - **Desktop (Linux/macOS/Windows):**
     ```bash
     flutter run -d linux
     ```
   - **Mobile (Emulator / Perangkat Terhubung):**
     ```bash
     flutter run
     ```

4. **Build untuk Produksi (Opsional):**
   Jika ingin menyajikan Web Flutter langsung melalui backend Rust:
   ```bash
   flutter build web --release
   ```
   Backend Core Rust secara otomatis membaca folder `frontend/build/web` dan menyajikannya di root `http://localhost:8000/`.

---

## 📌 Fitur Unggulan

- **Multi-Tenant & Multi-Branch:** Satu akun owner dapat mengelola tanpa batas unit toko/restoran/jasa.
- **ACID-Compliant POS Engine:** Transaksi kasir divalidasi dengan Row-Level Lock PostgreSQL untuk mencegah *overselling* atau *race condition* stok.
- **Smart Warehouse System:** Transfer stok antar cabang dengan alur verifikasi approval, stok opname, dan pengingat stok kritis otomatis.
- **AI Business Insights:** Analisis sentimen performa, rekomendasi otomatis restok, dan peramalan tren omzet.
- **Audit Logging:** Riwayat pelacakan modifikasi data dan aktivitas operasional untuk akuntabilitas.

---

## 📄 Lisensi

Hak Cipta © 2026 Proyek Rekayasa Perangkat Lunak Terpadu (IPPL). Semua hak dilindungi undang-undang.
