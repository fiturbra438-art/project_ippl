enum JenisTransaksi { pemasukan, pengeluaran }

class TransaksiModel {
  final int id;
  final int unitId;
  final String namaUnit;
  final DateTime tanggal;
  final JenisTransaksi jenis;
  final String kategori;
  final double jumlah;
  final String keterangan;

  TransaksiModel({
    required this.id,
    required this.unitId,
    required this.namaUnit,
    required this.tanggal,
    required this.jenis,
    required this.kategori,
    required this.jumlah,
    required this.keterangan,
  });
}

class TransaksiItemDetail {
  final int id;
  final int? productId;
  final String itemName;
  final String itemType;
  final int qty;
  final double hargaSatuan;
  final double subtotal;
  final int refundedQty;
  final int refundableQty;

  TransaksiItemDetail({
    required this.id,
    required this.productId,
    required this.itemName,
    required this.itemType,
    required this.qty,
    required this.hargaSatuan,
    required this.subtotal,
    required this.refundedQty,
    required this.refundableQty,
  });
}

class RefundItemModel {
  final int transactionItemId;
  final int? productId;
  final String itemName;
  final String itemType;
  final int qty;
  final double jumlah;

  RefundItemModel({
    required this.transactionItemId,
    required this.productId,
    required this.itemName,
    required this.itemType,
    required this.qty,
    required this.jumlah,
  });
}

class RefundModel {
  final int id;
  final int transactionId;
  final int unitId;
  final String jenis;
  final String alasan;
  final double jumlah;
  final String aktor;
  final DateTime createdAt;
  final List<RefundItemModel> items;

  RefundModel({
    required this.id,
    required this.transactionId,
    required this.unitId,
    required this.jenis,
    required this.alasan,
    required this.jumlah,
    required this.aktor,
    required this.createdAt,
    required this.items,
  });
}

class TransaksiDetailModel {
  final int id;
  final int unitId;
  final String namaUnit;
  final DateTime tanggal;
  final double total;
  final String metodeBayar;
  final String status;
  final String? customerName;
  final String? notes;
  final List<TransaksiItemDetail> items;
  final List<RefundModel> refunds;
  final double refundedTotal;
  final double refundableTotal;

  TransaksiDetailModel({
    required this.id,
    required this.unitId,
    required this.namaUnit,
    required this.tanggal,
    required this.total,
    required this.metodeBayar,
    required this.status,
    required this.customerName,
    required this.notes,
    required this.items,
    required this.refunds,
    required this.refundedTotal,
    required this.refundableTotal,
  });
}
