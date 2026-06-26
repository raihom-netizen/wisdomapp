/// Dados do prestador (empresa/pessoa) exibidos no cabeçalho do orçamento PDF.
class BudgetProvider {
  final String name;
  final String nomeFantasia;
  final String cpfCnpj;
  final String contact;
  final String address;
  final String logoUrl;

  const BudgetProvider({
    this.name = '',
    this.nomeFantasia = '',
    this.cpfCnpj = '',
    this.contact = '',
    this.address = '',
    this.logoUrl = '',
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'nomeFantasia': nomeFantasia,
        'cpfCnpj': cpfCnpj,
        'contact': contact,
        'address': address,
        'logoUrl': logoUrl,
      };

  static BudgetProvider fromMap(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return const BudgetProvider();
    return BudgetProvider(
      name: (data['name'] ?? '').toString(),
      nomeFantasia: (data['nomeFantasia'] ?? '').toString(),
      cpfCnpj: (data['cpfCnpj'] ?? '').toString(),
      contact: (data['contact'] ?? '').toString(),
      address: (data['address'] ?? '').toString(),
      logoUrl: (data['logoUrl'] ?? '').toString(),
    );
  }

  BudgetProvider copyWith({
    String? name,
    String? nomeFantasia,
    String? cpfCnpj,
    String? contact,
    String? address,
    String? logoUrl,
  }) =>
      BudgetProvider(
        name: name ?? this.name,
        nomeFantasia: nomeFantasia ?? this.nomeFantasia,
        cpfCnpj: cpfCnpj ?? this.cpfCnpj,
        contact: contact ?? this.contact,
        address: address ?? this.address,
        logoUrl: logoUrl ?? this.logoUrl,
      );

  bool get hasData => name.isNotEmpty || nomeFantasia.isNotEmpty || contact.isNotEmpty;
}
