const insertRecallTemplate = '''INSERT INTO recalls (
  Title,
  Active_Notice,
  States,
  Archive_Recall,
  Closed_Date,
  Closed_Year,
  Company_Media_Contact,
  Distro_List,
  En_Press_Release,
  Establishment,
  Labels,
  Media_Contact,
  Risk_Level,
  Last_Modified_Date,
  Press_Release,
  Processing,
  Product_Items,
  Qty_Recovered,
  Recall_Classification,
  Recall_Date,
  Recall_Number,
  Recall_Reason,
  Recall_Type,
  Related_To_Outbreak,
  Summary,
  Year,
  Langcode,
  Has_Spanish,
  Link
)
  VALUES
''';

const checkExist = '''SELECT *
FROM recalls
LIMIT 1;''';

const createDB = '''DROP TABLE IF EXISTS recalls;

CREATE TABLE recalls (
  Title                 TEXT,
  Active_Notice         TEXT,
  States                TEXT,
  Archive_Recall        TEXT,
  Closed_Date           TEXT,
  Closed_Year           TEXT,
  Company_Media_Contact TEXT,
  Distro_List           TEXT,
  En_Press_Release      TEXT,
  Establishment         TEXT,
  Labels                TEXT,
  Media_Contact         TEXT,
  Risk_Level            TEXT,
  Last_Modified_Date    TEXT,
  Press_Release         TEXT,
  Processing            TEXT,
  Product_Items         TEXT,
  Qty_Recovered         TEXT,
  Recall_Classification TEXT,
  Recall_Date           TEXT,
  Recall_Number         TEXT NOT NULL,
  Recall_Reason         TEXT,
  Recall_Type           TEXT,
  Related_To_Outbreak   TEXT,
  Summary               TEXT,
  Year                  TEXT,
  Langcode              TEXT NOT NULL,
  Has_Spanish           TEXT,
  Link                  TEXT,
  uri                   TEXT,
  cid                   TEXT,
  PRIMARY KEY (Recall_Number, Langcode)
)''';

const selectToPost = '''SELECT
  Recall_Number,
  Title,
  Recall_Date,
  States,
  Risk_Level,
  Recall_Reason,
  Recall_Type,
  Establishment,
  Link
FROM recalls
WHERE
  Langcode = 'English'
  AND uri IS NULL;''';
