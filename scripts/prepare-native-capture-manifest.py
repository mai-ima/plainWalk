"""Combine verified Simulator artifacts without publishing failed captures."""
from pathlib import Path
import argparse, datetime, json

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument("--allow-partial", action="store_true")
parser.add_argument("--source-commit")
args = parser.parse_args()
folder = root / "artifacts/previews/native-all"
catalog = json.loads((root / "scripts/native-screen-catalog.json").read_text())
groups = sorted({s["group"] for s in catalog["scenes"]})
labels = {"map":"白地図", "settings":"設定", "records":"記録", "profile":"プロフィール",
          "layers":"地図レイヤー", "answer":"答え合わせ", "spots":"ここいいな", "doodles":"らくがき",
          "menu":"メニュー", "stepGoal":"歩数の目標", "lut":"LUT", "spot":"写真を追加",
          "noteEditor":"ノート", "developer":"実機検証"}
rows = []
baseline = folder / "baseline"
source = (baseline / "source-commit.txt").read_text().strip()
if args.source_commit and source != args.source_commit:
    raise SystemExit("Baseline artifact source commit differs")
for key, title in labels.items():
    filename = "ios-native-" + key + ".png"
    if not (baseline / filename).is_file():
        raise SystemExit("Missing baseline frame: " + filename)
    rows.append(dict(key="baseline-"+key, title=title, category="基本画面", state="空・初期状態",
                     path="baseline/"+filename, part=1, sourceRoute=key, status="captured", sourceCommit=source))
pending = []
for group in groups:
    path = folder / group / "manifest.json"
    data = json.loads(path.read_text()) if path.is_file() else None
    valid = data is not None and data.get("complete") is True
    if valid:
        expected = {s["key"] for s in catalog["scenes"] if s["group"] == group}
        actual = {s["key"] for s in data["screens"]}
        valid = actual == expected and all(s.get("status") == "captured" and s.get("textVerified") is True for s in data["screens"])
        if args.source_commit and data.get("sourceCommit") != args.source_commit:
            valid = False
    if not valid:
        pending.append(group)
        continue
    for item in data["screens"]:
        filename = item["path"]
        if Path(filename).name != filename or not (folder/group/filename).is_file():
            raise SystemExit("Missing or invalid screenshot path")
        rows.append({**item, "path":group+"/"+filename, "sourceCommit":data.get("sourceCommit")})
if pending and not args.allow_partial:
    raise SystemExit("Unverified capture groups: " + ", ".join(pending))
limitations = list(catalog["limitations"])
expected_frames = len(labels) + len(catalog["scenes"])
if pending:
    limitations.insert(0, f"Swift版は予定{expected_frames}区間のうち、確認できた{len(rows)}枚を掲載しています。残りの区間は検証中です。")
result = dict(version=1, platform="native", engine="iPhone Simulator", complete=True,
              coverageComplete=not pending, expectedFrames=expected_frames, capturedFrames=len(rows), pendingGroups=pending,
              generatedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(), screens=rows, limitations=limitations)
(folder/"manifest.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
print(json.dumps({"nativeFrames":len(rows), "expectedFrames":expected_frames, "pendingGroups":pending}))
