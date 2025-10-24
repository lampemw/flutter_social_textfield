// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_social_textfield/flutter_social_textfield.dart';

class DetectionTextStyle {
  final TextStyle validTextStyle;
  final TextStyle? invalidTextStyle;
  DetectionTextStyle({
    required this.validTextStyle,
    this.invalidTextStyle,
  });
}

///An improved [TextEditingController] for using with any widget that accepts [TextEditingController].
///It uses [SocialTextSpanBuilder] for rendering the content.
///[_detectionStream] returns content of the current cursor position. Positions are calculated by the cyrrent location of the word
///Configuration is made by calling setter functions.
///example:
///     _textEditingController = SocialTextEditingController()
///       ..setTextStyle(DetectedType.mention, TextStyle(color: Colors.purple,backgroundColor: Colors.purple.withAlpha(50)))
///      ..setTextStyle(DetectedType.url, TextStyle(color: Colors.blue, decoration: TextDecoration.underline))
///      ..setTextStyle(DetectedType.hashtag, TextStyle(color: Colors.blue, fontWeight: FontWeight.w600))
///      ..setRegexp(DetectedType.mention, Regexp("your_custom_regex_pattern");
///
///There is also a helper function that can replaces range with the given value. In order to change cursor context, cursor moves to next word after replacement.
///
class SocialTextEditingController extends TextEditingController {
  StreamController<SocialContentDetection> _detectionStream =
      StreamController<SocialContentDetection>.broadcast();

  @override
  void dispose() {
    _detectionStream.close();
    super.dispose();
  }

  final Map<DetectedType, DetectionTextStyle> detectionTextStyles = Map();

  /// Function to validate workflow variables. Returns true if valid, false otherwise.
  /// The function receives the variable name (without {{ }} braces) as a parameter.
  bool Function(String variableName)? workflowVariableValidator;

  final Map<DetectedType, RegExp> _regularExpressions = {
    DetectedType.mention: atSignRegExp,
    DetectedType.hashtag: hashTagRegExp,
    DetectedType.url: urlRegex,
    DetectedType.emoji: emojiRegex,
    DetectedType.workflow_variable: workflowVariableRegExp,
  };

  StreamSubscription<SocialContentDetection> subscribeToDetection(
      Function(SocialContentDetection detected) listener) {
    return _detectionStream.stream.listen(listener);
  }

  void setTextStyle(DetectedType type, DetectionTextStyle style) {
    detectionTextStyles[type] = style;
  }

  void setRegexp(DetectedType type, RegExp regExp) {
    _regularExpressions[type] = regExp;
  }

  /// Sets the validator function for variables.
  /// The function should return true for valid variables, false for invalid ones.
  void setWorkflowVariableValidator(
      bool Function(String variableName) validator) {
    workflowVariableValidator = validator;
  }

  void replaceRange(String newValue, TextRange range) {
    var newText = text.replaceRange(range.start, range.end, newValue);
    var newRange =
        TextRange(start: range.start, end: range.start + newValue.length);
    bool isAtTheEndOfText = (newRange.textAfter(newText) == " " &&
        newRange.end == newText.length - 1);
    if (isAtTheEndOfText) {
      newText += " ";
    }
    TextSelection newTextSelection = TextSelection(
        baseOffset: newRange.end + 1, extentOffset: newRange.end + 1);
    value = value.copyWith(text: newText, selection: newTextSelection);
  }

  void _processNewValue(TextEditingValue newValue) {
    var currentPosition = newValue.selection.baseOffset;
    if (currentPosition == -1) {
      currentPosition = 0;
    }
    if (currentPosition > newValue.text.length) {
      currentPosition = newValue.text.length - 1;
    }

    // First, check if cursor is inside a {{ }} workflow variable
    var workflowVariableMatch =
        _findWorkflowVariableAtPosition(newValue.text, currentPosition);
    if (workflowVariableMatch != null) {
      _detectionStream.add(SocialContentDetection(
          DetectedType.workflow_variable,
          TextRange(
              start: workflowVariableMatch['start'],
              end: workflowVariableMatch['end']),
          workflowVariableMatch['content']));
      return;
    }

    // Also check if cursor is inside a {{  workflow variable start braces
    var workflowVariableStartMatch =
        _findWorkflowVariableStartAtPosition(newValue.text, currentPosition);
    if (workflowVariableStartMatch != null) {
      _detectionStream.add(SocialContentDetection(
          DetectedType.workflow_variable,
          TextRange(
              start: workflowVariableStartMatch['start'],
              end: workflowVariableStartMatch['end']),
          workflowVariableStartMatch['content']));
      return;
    }

    // Fall back to original word detection logic
    var subString = newValue.text.substring(0, currentPosition);
    var lastPart = subString.split(" ").last.split("\n").last;
    var startIndex = currentPosition - lastPart.length;
    var detectionContent =
        newValue.text.substring(startIndex).split(" ").first.split("\n").first;
    _detectionStream.add(SocialContentDetection(
        getType(detectionContent),
        TextRange(start: startIndex, end: startIndex + detectionContent.length),
        detectionContent));
  }

  /// Finds if the cursor position is inside a {{ }} workflow variable
  /// Returns a map with 'content', 'start', and 'end' if found, null otherwise
  Map<String, dynamic>? _findWorkflowVariableAtPosition(
      String text, int position) {
    // Find all workflow variable matches
    var matches = workflowVariableRegExp.allMatches(text);

    for (var match in matches) {
      // Check if cursor is within this workflow variable
      if (position >= match.start && position <= match.end) {
        return {
          'content': match.group(0), // Full match including {{ }}
          'start': match.start,
          'end': match.end,
        };
      }
    }

    return null;
  }

  /// Finds if the cursor position is inside a {{ }} workflow variable
  /// Returns a map with 'content', 'start', and 'end' if found, null otherwise
  Map<String, dynamic>? _findWorkflowVariableStartAtPosition(
      String text, int position) {
    // Find all workflow variable matches
    var matches = workflowVariableStartRegExp.allMatches(text);

    for (var match in matches) {
      // Check if cursor is within this workflow variable
      if (position >= match.start && position <= match.end) {
        return {
          'content': match.group(0), // Full match including {{
          'start': match.start,
          'end': match.end,
        };
      }
    }

    return null;
  }

  DetectedType getType(String word) {
    return _regularExpressions.keys.firstWhere(
        (type) => _regularExpressions[type]!.hasMatch(word),
        orElse: () => DetectedType.plain_text);
  }

  @override
  set value(TextEditingValue newValue) {
    if (newValue.selection.baseOffset >= newValue.text.length) {
      newValue = newValue.copyWith(
          text: newValue.text.trimRight() + " ",
          selection: newValue.selection.copyWith(
              baseOffset: newValue.text.length,
              extentOffset: newValue.text.length));
    }
    if (newValue.text == " ") {
      newValue = newValue.copyWith(
          text: "",
          selection:
              newValue.selection.copyWith(baseOffset: 0, extentOffset: 0));
    }

    _processNewValue(newValue);
    super.value = newValue;
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    return SocialTextSpanBuilder(
            regularExpressions: _regularExpressions,
            defaultTextStyle: style,
            detectionTextStyles: detectionTextStyles,
            workflowVariableValidator: workflowVariableValidator)
        .build(text);
  }
}
