import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// A new UUID v4. Ids from this function do not repeat after a restart.
String newId() => _uuid.v4();
