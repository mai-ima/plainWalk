const $ = id => document.getElementById(id);
const names = { ipa: "PlainWalk-iPhone-unsigned.ipa", playgrounds: "PlainWalk.swiftpm.zip" };
const validHash = value => typeof value === "string" && /^[0-9a-f]{64}$/i.test(value);
const validCommit = value => typeof value === "string" && /^[0-9a-f]{40}$/i.test(value);
const validBytes = value => Number.isSafeInteger(value) && value > 0;
const fileSize = bytes => bytes < 1024 * 1024 ? `${Math.max(1, Math.round(bytes / 1024))} KB` : `${(bytes / (1024 * 1024)).toLocaleString("ja-JP", { maximumFractionDigits: 1 })} MB`;
function validBuild(build) {
  return build && build.available === true && build.filename === names.ipa &&
    build.platform === "iPhoneOS" && build.architecture === "arm64" &&
    build.signing === "unsigned" && build.installableAsDownloaded === false &&
    validHash(build.sha256) && validBytes(build.bytes) && validCommit(build.sourceCommit) &&
    typeof build.minimumIOS === "string" && /^\d{1,2}\.\d{1,2}(?:\.\d{1,2})?$/.test(build.minimumIOS) &&
    build.playgrounds && build.playgrounds.filename === names.playgrounds &&
    validHash(build.playgrounds.sha256) && validBytes(build.playgrounds.bytes) && validCommit(build.playgrounds.sourceCommit);
}
function clearLinks() {
  for (const id of ["ipaDownload", "playgroundsDownload"]) {
    $(id).hidden = true;
    $(id).removeAttribute("href");
  }
  for (const id of ["ipaSummary", "buildDetails", "playgroundsDetails"]) $(id).hidden = true;
  $("playgroundsSummary").textContent = "配布ファイルを確認すると、保存リンクが表示されます。";
}
let request = null;
async function loadBuild() {
  request?.abort();
  const controller = new AbortController();
  request = controller;
  const timeout = setTimeout(() => controller.abort(), 8000);
  clearLinks();
  $("downloadRetry").hidden = true;
  $("downloadRetry").disabled = true;
  $("downloadStatus").dataset.state = "loading";
  $("downloadStatus").textContent = "保存するファイルを確認しています…";
  try {
    const response = await fetch("./build.json", { cache: "no-store", credentials: "same-origin", redirect: "error", signal: controller.signal });
    if (!response.ok) throw Error("metadata unavailable");
    const build = await response.json();
    if (request !== controller) return;
    if (build?.available === false) {
      $("downloadStatus").dataset.state = "pending";
      $("downloadStatus").textContent = "iPhone 用ファイルを準備しています。確認が終わると、ここから保存できます。";
      $("downloadRetry").hidden = false;
      return;
    }
    if (!validBuild(build)) throw Error("invalid build metadata");
    $("ipaDownload").href = `./${names.ipa}`;
    $("playgroundsDownload").href = `./${names.playgrounds}`;
    for (const id of ["ipaDownload", "playgroundsDownload", "ipaSummary", "buildDetails", "playgroundsDetails"]) $(id).hidden = false;
    $("downloadStatus").dataset.state = "ready";
    $("downloadStatus").textContent = "保存するファイルを確認しました。";
    $("ipaSummary").textContent = `iOS ${build.minimumIOS} 以降 · ${fileSize(build.bytes)}`;
    $("ipaHash").textContent = build.sha256.toLowerCase();
    $("sourceLink").textContent = build.sourceCommit;
    $("sourceLink").href = `https://github.com/mai-ima/plainWalk/commit/${build.sourceCommit}`;
    $("playgroundsSummary").textContent = `${fileSize(build.playgrounds.bytes)} · iPad / Mac 向け`;
    $("playgroundsHash").textContent = build.playgrounds.sha256.toLowerCase();
    $("playgroundsSource").textContent = build.playgrounds.sourceCommit;
  } catch {
    if (request !== controller) return;
    clearLinks();
    $("downloadStatus").dataset.state = "error";
    $("downloadStatus").textContent = "配布ファイルを確認できませんでした。通信を確認して、もう一度お試しください。Safari で開き直すと確認できる場合があります。";
    $("downloadRetry").hidden = false;
  } finally {
    clearTimeout(timeout);
    if (request === controller) $("downloadRetry").disabled = false;
  }
}
$("downloadRetry").addEventListener("click", loadBuild);
loadBuild();
