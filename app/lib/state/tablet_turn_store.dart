import '../domain/ink.dart';

/// Remembers which way the tablet is turned between launches.
abstract interface class TabletTurnStore {
  Future<TabletTurn?> read();

  Future<void> write(TabletTurn turn);
}

final class MemoryTabletTurnStore implements TabletTurnStore {
  TabletTurn? value;

  @override
  Future<TabletTurn?> read() async => value;

  @override
  Future<void> write(TabletTurn turn) async {
    value = turn;
  }
}
