import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  
  const Failure(this.message);
  
  @override
  List<Object> get props => [message];
}

class SpeechFailure extends Failure {
  const SpeechFailure(super.message);
}

class OverlayFailure extends Failure {
  const OverlayFailure(super.message);
}

class SpellCheckFailure extends Failure {
  const SpellCheckFailure(super.message);
}

class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}

