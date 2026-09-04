typedef RuntimeMap = Map<String, dynamic>;

final class EvaluationContext {
  EvaluationContext({
    this.locals = const <String, dynamic>{},
    this.contextState = const <String, dynamic>{},
    Map<String, RuntimeMap>? nodeResults,
  }) : nodeResults = nodeResults ?? <String, RuntimeMap>{};

  final Map<String, dynamic> locals;
  final Map<String, dynamic> contextState;
  final Map<String, RuntimeMap> nodeResults;
}

dynamic evaluateExpression(dynamic expression, EvaluationContext context) {
  if (expression is! Map) return null;
  final type = expression['type'];
  switch (type) {
    case 'literal':
      return expression['value'];
    case 'variable':
      final name = expression['name'];
      if (name is! String) return null;
      return context.locals.containsKey(name)
          ? context.locals[name]
          : context.contextState[name];
    case 'port':
      final nodeId = expression['nodeId'];
      final port = expression['port'];
      if (nodeId is! String || port is! String) return null;
      return context.nodeResults[nodeId]?[port];
    case 'binary':
      return _binary(
        expression['op'],
        evaluateExpression(expression['left'], context),
        evaluateExpression(expression['right'], context),
      );
    case 'unary':
      return _unary(
        expression['op'],
        evaluateExpression(expression['operand'], context),
      );
    case 'member':
      final object = evaluateExpression(expression['object'], context);
      final property = expression['property'];
      if (object is! Map || property is! String || _unsafe(property)) {
        return null;
      }
      return object[property];
    case 'index':
      final object = evaluateExpression(expression['object'], context);
      final index = evaluateExpression(expression['index'], context);
      if (_unsafe(index)) return null;
      if (object is Map) return object[index];
      if (object is List &&
          index is int &&
          index >= 0 &&
          index < object.length) {
        return object[index];
      }
      if (object is String &&
          index is int &&
          index >= 0 &&
          index < object.length) {
        return object[index];
      }
      return null;
    case 'call':
      final args =
          (expression['args'] is List ? expression['args'] as List : const [])
              .map((arg) => evaluateExpression(arg, context))
              .toList();
      return _builtin(expression['fn'], args);
    default:
      throw ArgumentError('Unknown expression type: $type');
  }
}

dynamic _binary(dynamic operator, dynamic left, dynamic right) {
  switch (operator) {
    case '==':
      return left == right;
    case '!=':
      return left != right;
    case '>':
      return left is Comparable && right is Comparable
          ? left.compareTo(right) > 0
          : false;
    case '<':
      return left is Comparable && right is Comparable
          ? left.compareTo(right) < 0
          : false;
    case '>=':
      return left is Comparable && right is Comparable
          ? left.compareTo(right) >= 0
          : false;
    case '<=':
      return left is Comparable && right is Comparable
          ? left.compareTo(right) <= 0
          : false;
    case '&&':
      return _truthy(left) ? right : left;
    case '||':
      return _truthy(left) ? left : right;
    case '+':
      return left is String || right is String
          ? '$left$right'
          : _number(left) + _number(right);
    case '-':
      return _number(left) - _number(right);
    case '*':
      return _number(left) * _number(right);
    case '/':
      if (_number(right) == 0) throw StateError('Division by zero');
      return _number(left) / _number(right);
    case '%':
      if (_number(right) == 0) throw StateError('Modulo by zero');
      return _number(left) % _number(right);
    default:
      throw ArgumentError('Unknown binary operator: $operator');
  }
}

dynamic _unary(dynamic operator, dynamic operand) {
  switch (operator) {
    case '!':
      return !_truthy(operand);
    case '-':
      return -_number(operand);
    case 'typeof':
      return _typeOf(operand);
    default:
      throw ArgumentError('Unknown unary operator: $operator');
  }
}

dynamic _builtin(dynamic function, List<dynamic> args) {
  final target = args.isEmpty ? null : args.first;
  switch (function) {
    case 'len':
      return target is Iterable || target is String ? target.length : 0;
    case 'includes':
      return target is Iterable
          ? target.contains(args.elementAtOrNull(1))
          : target is String
          ? target.contains('${args.elementAtOrNull(1) ?? ''}')
          : false;
    case 'startsWith':
      return target is String &&
          target.startsWith('${args.elementAtOrNull(1) ?? ''}');
    case 'endsWith':
      return target is String &&
          target.endsWith('${args.elementAtOrNull(1) ?? ''}');
    case 'toString':
      return target?.toString() ?? '';
    case 'toNumber':
      return _number(target);
    case 'toBoolean':
      return _truthy(target);
    case 'floor':
      return _number(target).floor();
    case 'ceil':
      return _number(target).ceil();
    case 'round':
      return _number(target).round();
    case 'abs':
      return _number(target).abs();
    case 'min':
      return _numbers(args).isEmpty
          ? null
          : _numbers(args).reduce((a, b) => a < b ? a : b);
    case 'max':
      return _numbers(args).isEmpty
          ? null
          : _numbers(args).reduce((a, b) => a > b ? a : b);
    case 'keys':
      return target is Map ? target.keys.toList() : <dynamic>[];
    case 'values':
      return target is Map ? target.values.toList() : <dynamic>[];
    case 'slice':
      final start = _number(args.elementAtOrNull(1)).toInt();
      final end = args.length > 2 ? _number(args[2]).toInt() : null;
      if (target is List) {
        return target.sublist(
          start.clamp(0, target.length),
          end?.clamp(0, target.length),
        );
      }
      if (target is String) {
        return target.substring(
          start.clamp(0, target.length),
          end?.clamp(0, target.length),
        );
      }
      return target;
    case 'concat':
      if (target is List) {
        return [
          ...target,
          ...(args.elementAtOrNull(1) is List ? args[1] as List : const []),
        ];
      }
      if (target is String) return '$target${args.elementAtOrNull(1) ?? ''}';
      return target;
    default:
      throw ArgumentError('Unknown builtin function: $function');
  }
}

num _number(dynamic value) =>
    value is num ? value : num.tryParse('$value') ?? 0;
bool _truthy(dynamic value) => value is bool
    ? value
    : value != null && value != 0 && value != '' && value != false;
String _typeOf(dynamic value) => value == null
    ? 'undefined'
    : value is bool
    ? 'boolean'
    : value is num
    ? 'number'
    : value is String
    ? 'string'
    : 'object';
bool _unsafe(dynamic value) =>
    value == '__proto__' || value == 'constructor' || value == 'prototype';
List<num> _numbers(List<dynamic> values) =>
    values.skip(1).whereType<num>().toList();

extension<T> on List<T> {
  T? elementAtOrNull(int index) => index < length ? this[index] : null;
}
