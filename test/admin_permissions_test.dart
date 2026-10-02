import 'package:flutter_test/flutter_test.dart';
import 'package:controle_total_premium/services/admin_permissions_service.dart';
import 'package:controle_total_premium/widgets/admin_menu_lateral.dart';

void main() {
  const svc = AdminPermissionsService();

  group('master só por e-mail de dono verificado', () {
    test('raihom verificado = master', () {
      expect(
        svc.capabilityFor(
            role: 'user', email: 'raihom@gmail.com', emailVerified: true),
        AdminCapability.superAdmin,
      );
    });
    test('isabelle verificada = master', () {
      expect(
        svc.capabilityFor(
            role: 'admin',
            email: 'Isabelle.Krdoso@gmail.com',
            emailVerified: true),
        AdminCapability.superAdmin,
      );
    });
    test('e-mail de dono sem verificação NÃO é master', () {
      expect(
        svc.capabilityFor(
            role: 'admin', email: 'raihom@gmail.com', emailVerified: false),
        AdminCapability.admin,
      );
    });
    test('role master gravado sem ser dono = administrador comum', () {
      expect(
        svc.capabilityFor(
            role: 'master', email: 'x@x.com', emailVerified: true),
        AdminCapability.admin,
      );
    });
    test('override adminCapability master não dá master', () {
      expect(
        svc.capabilityFor(
            role: 'admin',
            email: 'x@x.com',
            emailVerified: true,
            adminCapabilityOverride: 'master'),
        AdminCapability.admin,
      );
    });
  });

  group('adminLevel restringe de verdade', () {
    test('suporte', () {
      final c = svc.capabilityFor(
          role: 'admin', email: 's@x.com', adminLevel: 'suporte');
      expect(c, AdminCapability.support);
      expect(svc.canAccessMenuItem(c, AdminMenuItem.usuarios), isTrue);
      expect(svc.canEditUserLicense(c), isTrue);
      expect(svc.canAccessMenuItem(c, AdminMenuItem.mercadopago), isFalse);
      expect(svc.canAccessMenuItem(c, AdminMenuItem.drive), isFalse);
      expect(svc.canAccessMenuItem(c, AdminMenuItem.receitasDespesas), isFalse);
      expect(svc.canDeleteUserPermanent(c), isFalse);
    });
    test('editor', () {
      final c =
          svc.capabilityFor(role: 'admin', email: 'e@x.com', adminLevel: 'editor');
      expect(c, AdminCapability.editor);
      expect(svc.canAccessMenuItem(c, AdminMenuItem.landing), isTrue);
      expect(svc.canAccessMenuItem(c, AdminMenuItem.escala), isTrue);
      expect(svc.canAccessMenuItem(c, AdminMenuItem.usuarios), isFalse);
      expect(svc.canEditUserLicense(c), isFalse);
    });
    test('administrador não acessa o que é só do master', () {
      final c = svc.capabilityFor(role: 'admin', email: 'a@x.com');
      expect(c, AdminCapability.admin);
      for (final i in AdminPermissionsService.kMasterOnlyItems) {
        expect(svc.canAccessMenuItem(c, i), isFalse, reason: '$i');
      }
      expect(svc.canAccessMenuItem(c, AdminMenuItem.usuarios), isTrue);
      expect(svc.canManageTeam(c), isFalse);
      expect(svc.canEditMercadoPagoConfig(c), isFalse);
    });
    test('master vê tudo, inclusive Promover a admin', () {
      final c = svc.capabilityFor(
          role: 'user', email: 'raihom@gmail.com', emailVerified: true);
      expect(svc.canAccessMenuItem(c, AdminMenuItem.promoverAdmin), isTrue);
      expect(svc.canAccessMenuItem(c, AdminMenuItem.drive), isTrue);
      expect(svc.canManageTeam(c), isTrue);
    });
    test('editor de conteúdo segue só Cursos + Dicas', () {
      final c = svc.capabilityFor(role: 'editor_conteudo', email: 't@x.com');
      expect(svc.allowedMenuItems(c).toSet(),
          {AdminMenuItem.cursos, AdminMenuItem.dicasFinanceiras});
    });
  });
}
