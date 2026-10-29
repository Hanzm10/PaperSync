import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/simulated_pen_transport.dart';
import 'package:papersync/domain/ink.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/notebook_store_provider.dart';
import 'package:papersync/state/pen_transport_provider.dart';
import 'package:papersync/storage/notebook_store.dart';

final _t0 = DateTime.utc(2026, 10, 29);

Notebook _notebook(String id, String name) => Notebook(
  id: id,
  name: name,
  inkColorArgb: 0xFF000000,
  createdAt: _t0,
  pages: const [],
);

void main() {
  test('notebooks that sync adds to the store reach the screens', () async {
    final store = MemoryNotebookStore(
      notebooks: [_notebook('nb-phone', 'Written on the phone')],
    );
    final container = ProviderContainer(
      overrides: [
        notebookStoreProvider.overrideWithValue(store),
        penTransportProvider.overrideWithValue(
          SimulatedPenTransport(
            clock: () => _t0,
            seed: 3,
            scenario: PenScenario.normalWriting,
            manual: true,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final before = container.read(appControllerProvider);
    final phone = before.notebook('nb-phone');
    expect(phone, isNotNull);

    // What a sync does: the store changes without the controller.
    await store.createNotebook(_notebook('nb-web', 'From the website'));
    expect(container.read(appControllerProvider).notebook('nb-web'), isNull);

    container.read(appControllerProvider.notifier).reloadFromStore();
    final after = container.read(appControllerProvider);
    expect(after.notebook('nb-web')?.name, 'From the website');
    expect(identical(after.notebook('nb-phone'), phone), isTrue);
  });
}
