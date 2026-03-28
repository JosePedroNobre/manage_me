import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

class ClaudeService {
  static const String _bridgeBase = 'http://localhost:9091';
  final String apiKey;
  final String projectPath;
  ClaudeService({required this.apiKey, this.projectPath = ''});

  /// Review a PR — streams logs via callback, returns final result.
  Future<ClaudeReview> reviewPR({
    required String prTitle,
    required String prDescription,
    required List<Map<String, dynamic>> files,
    void Function(String line)? onLog,
  }) async {
    final diffBuf = StringBuffer();
    for (final f in files) {
      diffBuf.writeln('--- ${f['filename'] ?? f['new_path'] ?? ''} ---');
      diffBuf.writeln(f['patch'] ?? '');
    }

    final result = await _streamRequest('$_bridgeBase/review', {
      'prTitle': prTitle,
      'prDescription': prDescription,
      'diff': diffBuf.toString(),
      'projectPath': projectPath,
    }, onLog: onLog);

    final comments = (result['comments'] as List?) ?? [];
    return ClaudeReview(
      comments: comments.map((c) => ClaudeComment(file: c['file'] ?? '', comment: c['comment'] ?? '', severity: c['severity'] ?? 'info')).toList(),
      raw: result['raw'] ?? '',
    );
  }

  /// Plan a Jira ticket — streams logs via callback.
  Future<ImplementationPlan> planTicket({
    required String key,
    required String summary,
    required String description,
    String type = 'task',
    String priority = '',
    List<Map<String, String>> images = const [],
    void Function(String line)? onLog,
  }) async {
    final result = await _streamRequest('$_bridgeBase/implement', {
      'key': key,
      'summary': summary,
      'description': description,
      'type': type,
      'priority': priority,
      'projectPath': projectPath,
      'images': images,
    }, onLog: onLog);

    final plan = result['plan'] ?? {};
    final rawFiles = plan['files'] ?? [];
    final files = <FileChange>[];
    for (final f in rawFiles) {
      if (f is Map) {
        files.add(FileChange(path: f['path'] ?? '', changes: f['changes'] ?? ''));
      } else if (f is String) {
        files.add(FileChange(path: f, changes: ''));
      }
    }

    return ImplementationPlan(
      files: files,
      edgeCases: List<String>.from(plan['edge_cases'] ?? []),
      raw: result['raw'] ?? '',
    );
  }

  /// Send a free-form prompt to Claude with optional context.
  Future<String> sendPrompt({
    required String prompt,
    String context = '',
    void Function(String chunk)? onLog,
  }) async {
    final result = await _streamRequest('$_bridgeBase/prompt', {
      'prompt': prompt,
      'context': context,
      'projectPath': projectPath,
    }, onLog: onLog);
    return result['raw'] ?? '';
  }

  /// Makes a POST request and reads SSE stream.
  Future<Map<String, dynamic>> _streamRequest(String url, Map<String, dynamic> body, {void Function(String)? onLog}) async {
    final request = http.Request('POST', Uri.parse(url));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final response = await client.send(request).timeout(const Duration(seconds: 150));

      if (response.statusCode != 200) {
        final respBody = await response.stream.bytesToString();
        try {
          final err = jsonDecode(respBody);
          throw Exception(err['error'] ?? 'Bridge error ${response.statusCode}');
        } catch (e) {
          if (e is Exception) rethrow;
          throw Exception('Bridge error ${response.statusCode}');
        }
      }

      Map<String, dynamic> finalResult = {};
      final buffer = StringBuffer();

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer.write(chunk);
        // Parse SSE lines
        final raw = buffer.toString();
        final lines = raw.split('\n');
        buffer.clear();
        // Keep incomplete last line in buffer
        if (!raw.endsWith('\n')) {
          buffer.write(lines.removeLast());
        }

        for (final line in lines) {
          if (!line.startsWith('data: ')) continue;
          final jsonStr = line.substring(6).trim();
          if (jsonStr.isEmpty) continue;
          try {
            final event = jsonDecode(jsonStr);
            if (event['type'] == 'text') {
              onLog?.call(event['text'] ?? '');
            } else if (event['type'] == 'done') {
              finalResult = event;
            }
          } catch (_) {}
        }
      }

      return finalResult;
    } finally {
      client.close();
    }
  }
}

class FileChange {
  final String path;
  final String changes;
  FileChange({required this.path, required this.changes});
}

class ImplementationPlan {
  final List<FileChange> files;
  final List<String> edgeCases;
  final String raw;
  ImplementationPlan({required this.files, required this.edgeCases, required this.raw});
}

class ClaudeReview {
  final List<ClaudeComment> comments;
  final String raw;
  ClaudeReview({required this.comments, required this.raw});
}

class ClaudeComment {
  final String file;
  final String comment;
  final String severity;
  ClaudeComment({required this.file, required this.comment, required this.severity});
}
