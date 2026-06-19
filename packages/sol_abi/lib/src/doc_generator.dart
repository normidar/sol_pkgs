import 'dart:convert';
import 'package:sol_ast/sol_ast.dart';
import 'abi_signature.dart';
import 'natspec.dart';

/// Generates solc-compatible `userdoc` and `devdoc` JSON from the NatSpec
/// documentation attached to a contract and its members.
///
/// See https://docs.soliditylang.org/en/latest/natspec-format.html
class DocGenerator {
  /// End-user documentation (`@notice`, `@custom:`).
  Map<String, dynamic> userdoc(ContractDefinition contract) {
    final contractDoc = NatSpec.parse(contract.documentation);
    final methods = <String, dynamic>{};
    final events = <String, dynamic>{};
    final errors = <String, dynamic>{};

    for (final member in contract.members) {
      switch (member) {
        case FunctionDefinition fn when fn.name != null && _isExternal(fn):
          final doc = NatSpec.parse(fn.documentation);
          final entry = <String, dynamic>{};
          if (doc.notice != null) entry['notice'] = doc.notice;
          _addCustom(entry, doc);
          if (entry.isNotEmpty) methods[functionSignature(fn)] = entry;
        case EventDefinition ev:
          final doc = NatSpec.parse(ev.documentation);
          if (doc.notice != null) {
            events[eventSignature(ev)] = {'notice': doc.notice};
          }
        case CustomErrorDefinition err:
          final doc = NatSpec.parse(err.documentation);
          if (doc.notice != null) {
            errors[errorSignature(err)] = [
              {'notice': doc.notice},
            ];
          }
        default:
          break;
      }
    }

    return {
      'version': 1,
      'kind': 'user',
      if (contractDoc.notice != null) 'notice': contractDoc.notice,
      'methods': methods,
      'events': events,
      'errors': errors,
    };
  }

  /// Developer documentation (`@title`, `@author`, `@dev`, `@param`,
  /// `@return`).
  Map<String, dynamic> devdoc(ContractDefinition contract) {
    final contractDoc = NatSpec.parse(contract.documentation);
    final methods = <String, dynamic>{};
    final events = <String, dynamic>{};
    final errors = <String, dynamic>{};
    final stateVariables = <String, dynamic>{};

    for (final member in contract.members) {
      switch (member) {
        case FunctionDefinition fn when fn.name != null && _isExternal(fn):
          final entry = _devEntry(NatSpec.parse(fn.documentation), fn);
          if (entry.isNotEmpty) methods[functionSignature(fn)] = entry;
        case EventDefinition ev:
          final doc = NatSpec.parse(ev.documentation);
          final entry = <String, dynamic>{};
          if (doc.dev != null) entry['details'] = doc.dev;
          if (doc.params.isNotEmpty) entry['params'] = doc.params;
          _addCustom(entry, doc);
          if (entry.isNotEmpty) events[eventSignature(ev)] = entry;
        case CustomErrorDefinition err:
          final doc = NatSpec.parse(err.documentation);
          final entry = <String, dynamic>{};
          if (doc.dev != null) entry['details'] = doc.dev;
          if (doc.params.isNotEmpty) entry['params'] = doc.params;
          if (entry.isNotEmpty) {
            errors[errorSignature(err)] = [entry];
          }
        case StateVariableDeclaration sv
            when sv.visibility == Visibility.public:
          final doc = NatSpec.parse(sv.documentation);
          final entry = <String, dynamic>{};
          if (doc.dev != null) entry['details'] = doc.dev;
          if (entry.isNotEmpty) stateVariables[sv.name] = entry;
        default:
          break;
      }
    }

    return {
      'version': 1,
      'kind': 'dev',
      if (contractDoc.author != null) 'author': contractDoc.author,
      if (contractDoc.title != null) 'title': contractDoc.title,
      if (contractDoc.dev != null) 'details': contractDoc.dev,
      'methods': methods,
      if (events.isNotEmpty) 'events': events,
      if (errors.isNotEmpty) 'errors': errors,
      if (stateVariables.isNotEmpty) 'stateVariables': stateVariables,
    };
  }

  Map<String, dynamic> _devEntry(NatSpec doc, FunctionDefinition fn) {
    final entry = <String, dynamic>{};
    if (doc.dev != null) entry['details'] = doc.dev;
    if (doc.params.isNotEmpty) entry['params'] = doc.params;
    final returns = _returnsMap(doc, fn);
    if (returns.isNotEmpty) entry['returns'] = returns;
    _addCustom(entry, doc);
    return entry;
  }

  /// Maps `@return` entries onto return-parameter names (or `_0`, `_1`, …).
  Map<String, String> _returnsMap(NatSpec doc, FunctionDefinition fn) {
    final out = <String, String>{};
    for (var i = 0; i < doc.returns.length; i++) {
      final named = i < fn.returnParameters.length
          ? fn.returnParameters[i].name
          : null;
      final key = (named != null && named.isNotEmpty) ? named : '_$i';
      var text = doc.returns[i];
      // A named return may repeat its name as the first word; drop it.
      if (key != '_$i' && text.startsWith('$key ')) {
        text = text.substring(key.length + 1).trim();
      }
      out[key] = text;
    }
    return out;
  }

  void _addCustom(Map<String, dynamic> entry, NatSpec doc) {
    doc.custom.forEach((k, v) => entry['custom:$k'] = v);
  }

  static bool _isExternal(FunctionDefinition fn) =>
      fn.visibility == Visibility.public ||
      fn.visibility == Visibility.external;

  String userdocJson(ContractDefinition c) =>
      const JsonEncoder.withIndent('  ').convert(userdoc(c));

  String devdocJson(ContractDefinition c) =>
      const JsonEncoder.withIndent('  ').convert(devdoc(c));
}
