// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/services/persona_service.dart';
import 'fake_storage_service.dart';

void main() {
  late FakeStorageService storage;
  late PersonaService svc;

  setUp(() {
    storage = FakeStorageService();
    svc = PersonaService(storage: storage);
  });

  group('PersonaService', () {
    test('初始化自动创建默认人格', () {
      expect(svc.personas.length, 1);
      expect(svc.personas.first.name, '默认助手');
    });

    test('默认人格被选中', () {
      expect(svc.selected, isNotNull);
      expect(svc.selected!.name, '默认助手');
    });

    test('add 添加新人格', () async {
      await svc.add('码农', '你是一个程序员');
      expect(svc.personas.length, 2);
      expect(svc.personas.last.name, '码农');
    });

    test('selectAndSave 切换人格', () async {
      await svc.add('二号', 'system prompt 2');
      final newId = svc.personas.last.id;
      await svc.selectAndSave(newId);
      expect(svc.selected!.id, newId);
    });

    test('delete 删除人格', () async {
      await svc.add('待删', 'sp');
      final id = svc.personas.last.id;
      await svc.delete(id);
      expect(svc.personas.length, 1);
    });

    test('delete 不允许删除到最后 0 个', () async {
      final id = svc.personas.first.id;
      await svc.delete(id);
      expect(svc.personas.length, 1); // still 1
    });

    test('update 修改人格', () async {
      final id = svc.personas.first.id;
      await svc.update(id, name: '新名字', traits: '幽默');
      expect(svc.selected!.name, '新名字');
      expect(svc.selected!.traits, '幽默');
    });
  });
}
