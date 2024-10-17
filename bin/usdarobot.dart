import 'dart:convert';
import 'dart:io';

import 'package:dart_rss/dart_rss.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';
import 'package:bluesky/atproto.dart' as at;
import 'package:bluesky/bluesky.dart' as bsky;
import 'package:bluesky_text/bluesky_text.dart' as bskytxt;

import 'queries.dart' as qry;
import 'creds.dart' as cred;

void main(List<String> arguments) async {
  print("getting recalls");
  final apiRecalls = await _getAPIRecalls();
  if (apiRecalls.isEmpty) {
    print("no recalls returned by api");
    exit(1);
  }

  final rssRecalls = await _getRSSRecalls();
  if (rssRecalls.isEmpty) {
    print("no recalls returned by rss");
    exit(1);
  }

  print("opening database");
  final Database db;
  try {
    db = _openDatabase();
  } catch (e) {
    print(e);
    exit(1);
  }

  print("updating databse");
  final toPost = _insertRecalls(db, apiRecalls, rssRecalls);

  print("posting updates");
  if (toPost) {
    print("there are things to post");
    final postCount = await _postUpdates(db);
    print("$postCount updates posted");
    exit(0);
  }
  print("nothing to post");
  exit(0);
}

Future<List> _getAPIRecalls() async {
  print("_getAPIRecalls: getting recalls");
  final uri = Uri.https('www.fsis.usda.gov', 'fsis/api/recall/v/1');
  final http.Response resp;

  print("_getAPIRecalls: executing GET");
  try {
    resp = await http.get(uri);
  } catch (e) {
    print('_getAPIRecalls: $e');
    return [];
  }

  print("_getAPIRecalls: checking statuscode");
  if (resp.statusCode < 200 || resp.statusCode > 299) {
    print(
        '_getAPIRecalls: error. statuscode: ${resp.statusCode} body: ${resp.body}');
    return [];
  }

  print("_getAPIRecalls: parsing body");
  final dynamic body;
  try {
    body = jsonDecode(resp.body);
  } catch (e) {
    print('_getAPIRecalls: $e');
    print(
        '_getAPIRecalls: error. statuscode: ${resp.statusCode} body: ${resp.body}');
    return [];
  }

  print("_getAPIRecalls: veryfiying List<Map> returned");
  if (body is List) {
    print("_getAPIRecalls: returning List<Map>");
    return body;
  }

  print("_getAPIRecalls: List<Map> not returned");
  print(
      '_getAPIRecalls: error. statuscode: ${resp.statusCode} body: ${resp.body}');
  return [];
}

Future<Map<String, String>> _getRSSRecalls() async {
  print("_getRSSRecalls: getting recalls");
  final uri = Uri.https('www.fsis.usda.gov', 'fsis-content/rss/recalls.xml');
  final http.Response resp;

  print("_getRSSRecalls: executing GET");
  try {
    resp = await http.get(uri);
  } catch (e) {
    print('_getRSSRecalls: $e');
    return {};
  }

  print("_getRSSRecalls: checking statuscode");
  if (resp.statusCode < 200 || resp.statusCode > 299) {
    print(
        '_getRSSRecalls: error. statuscode: ${resp.statusCode} body: ${resp.body}');
    return {};
  }

  final Map<String, String> links = {};
  final channel = RssFeed.parse(resp.body);
  for (final item in channel.items) {
    if (item.title != null) {
      links[item.title!] = item.link!;
    }
  }

  return links;
}

bool _isNew(Database db) {
  final ResultSet results;
  try {
    results = db.select(qry.checkExist);
  } on SqliteException catch (e) {
    if (e.message == 'no such table: recalls') {
      return true;
    }
    print('_isNew: $e');
    rethrow;
  } catch (e) {
    print('_isNew: $e');
    rethrow;
  }
  return results.isEmpty;
}

void _initializeDB(Database db) {
  try {
    db.execute(qry.createDB);
  } catch (e) {
    print('_initializeDB: $e');
    rethrow;
  }
}

bool _insertRecalls(Database db, List recalls, Map<String, String> links) {
  var newRecalls = false;
  for (final r in recalls) {
    if (r is Map) {
      final String recallValue = _recallValue(r, links);
      final String qryInsertRecall = '''${qry.insertRecallTemplate}
$recallValue;''';
      try {
        db.execute(qryInsertRecall);
      } on SqliteException catch (e) {
        if (e.explanation == 'constraint failed (code 1555)') {
          continue;
        }
        print('_insertRecalls: $e');
        print(qryInsertRecall);
        continue;
      } catch (e) {
        print('_insertRecalls: $e');
        print(qryInsertRecall);

        continue;
      }
      newRecalls = true;
    } else {
      print("_insertRecalls: r is ${r.runtimeType}, not a Map");
      print(r);
    }
  }
  return newRecalls;
}

String _recallValue(Map r, Map l) {
  final List<String> values = [];
  for (final f in jsonFields) {
    values.add(_sanitizeSqlString(r[f]));
  }
  values.add(_sanitizeSqlString(l[r['field_title']] ?? ''));
  final String value = "('${values.join("','")}')";
  return value;
}

String _sanitizeSqlString(String s) {
  return s.replaceAll("'", "''");
}

Future<int> _postUpdates(Database db) async {
  var posted = 0;
  final ResultSet results;
  try {
    results = db.select(qry.selectToPost);
  } catch (e) {
    print('_postUpdates: $e');
    rethrow;
  }

  // final session = await at.createSession(
  //   identifier: cred.username,
  //   password: cred.password,
  // );

  // final bskysesh = bsky.Bluesky.fromSession(session.data);

  for (final r in results) {
    if (r['Title'] == null || r['Title'] == '') {
      print('_postUpdates: no title: $r');
      continue;
    }
    final List<at.StrongRef> titlerefs = [];
    for (final p in postTitles) {
      final post = _createPost(p, r);
      if (post.value.isEmpty) {
        continue;
      }
      for (final s in post.split()) {
        final bsky.ReplyRef? reply;
        if (titlerefs.isNotEmpty) {
          reply = bsky.ReplyRef(
            root: titlerefs.first,
            parent: titlerefs.last,
          );
        } else {
          reply = null;
        }

        final facets = await s.entities.toFacets();
        // final strongRef = await bskysesh.feed.post(
        //     text: post.value,
        //     reply: reply,
        //     facets: facets.map(bsky.Facet.fromJson).toList());
        // titlerefs.add(strongRef.data);

        ++posted;
        print(post.value);
      }
    }
  }

  return posted;
}

bskytxt.BlueskyText _createPost(List<List<String>> titles, Row r) {
  StringBuffer postText = StringBuffer();
  for (final t in titles) {
    final field = t[0];
    final header = t[1];
    final rawText = parser.parseFragment(r[field]).text;
    if (rawText != null && rawText != '') {
      rawText.replaceAll('  ', ' ');
      rawText.replaceAll('\n\n', '\n');
      if (header != '') {
        if (postText.isNotEmpty) {
          postText.write('\n');
        }
        postText.write('$header: ');
      }
      // TODO: Fix links for Labels
      postText.write(rawText);
    }
  }
  final text = bskytxt.BlueskyText(postText.toString());
  return text;
}

Database _openDatabase() {
  final String homeDir = Platform.environment['HOME'] ?? '';

  final databaseDir = Directory('$homeDir/.usdarecallbot');
  if (!databaseDir.existsSync()) {
    databaseDir.createSync();
  }

  final db = sqlite3.open('${databaseDir.path}/urb.db');

  if (_isNew(db)) {
    _initializeDB(db);
  }

  return db;
}

const List<String> jsonFields = [
  'field_title',
  'field_active_notice',
  'field_states',
  'field_archive_recall',
  'field_closed_date',
  'field_closed_year',
  'field_company_media_contact',
  'field_distro_list',
  'field_en_press_release',
  'field_establishment',
  'field_labels',
  'field_media_contact',
  'field_risk_level',
  'field_last_modified_date',
  'field_press_release',
  'field_processing',
  'field_product_items',
  'field_qty_recovered',
  'field_recall_classification',
  'field_recall_date',
  'field_recall_number',
  'field_recall_reason',
  'field_recall_type',
  'field_related_to_outbreak',
  'field_summary',
  'field_year',
  'langcode',
  'field_has_spanish',
];

const List<List<List<String>>> postTitles = [
  [
    ['Title', ''],
    ['Link', 'Link'],
  ],
  [
    ['Recall_Date', 'Recall Date'],
    ['States', 'States'],
  ],
  [
    ['Risk_Level', 'Risk Level'],
    ['Recall_Reason', 'Recall Reason'],
    ['Recall_Type', 'Recall Type'],
    ['Establishment', 'Establishment'],
  ],
];
