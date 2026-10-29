export async function readVideo(blob, knownDuration = null) {
  if (blob.size > 15 * 1024 * 1024)
    throw Error("動画は 15 MB 以下で選んでください。");
  if (!blob.type.startsWith("video/"))
    throw Error("動画ファイルを選んでください。");
  const url = URL.createObjectURL(blob),
    video = document.createElement("video");
  video.muted = true;
  video.playsInline = true;
  try {
    video.src = url;
    await new Promise((resolve, reject) => {
      video.onloadedmetadata = resolve;
      video.onerror = () =>
        reject(Error("この動画形式を読み取れません。MP4 をお試しください。"));
    });
    const duration = Number.isFinite(video.duration)
      ? video.duration
      : knownDuration;
    if (!Number.isFinite(duration) || duration > 2.6 || duration <= 0)
      throw Error("1〜2 秒の短い動画を選んでください。");
    video.currentTime = Math.min(0.1, video.duration / 2);
    await new Promise((resolve, reject) => {
      video.onseeked = resolve;
      video.onerror = () => reject(Error("動画の画像を読み取れません。"));
    });
    const scale = Math.min(
        1,
        720 / Math.max(video.videoWidth, video.videoHeight),
      ),
      canvas = document.createElement("canvas");
    canvas.width = Math.round(video.videoWidth * scale);
    canvas.height = Math.round(video.videoHeight * scale);
    canvas.getContext("2d").drawImage(video, 0, 0, canvas.width, canvas.height);
    const data = await new Promise((resolve, reject) => {
      const r = new FileReader();
      r.onload = () => resolve(r.result);
      r.onerror = () => reject(r.error);
      r.readAsDataURL(blob);
    });
    return {
      data,
      poster: canvas.toDataURL("image/jpeg", 0.75),
      duration,
      mime: blob.type,
    };
  } finally {
    URL.revokeObjectURL(url);
    video.removeAttribute("src");
    video.load();
  }
}
export async function openCamera(video, audio) {
  if (!navigator.mediaDevices?.getUserMedia)
    throw Error(
      "この環境ではブラウザ撮影に対応していません。短い動画ファイルを選んでください。",
    );
  const stream = await navigator.mediaDevices.getUserMedia({
    video: {
      facingMode: "environment",
      width: { ideal: 720 },
      height: { ideal: 1280 },
    },
    audio: !!audio,
  });
  video.srcObject = stream;
  video.hidden = false;
  await video.play();
  return stream;
}
export function captureTwoSeconds(stream) {
  if (!window.MediaRecorder)
    throw Error("このブラウザでは動画撮影に対応していません。");
  const mime = ["video/mp4", "video/webm;codecs=vp9", "video/webm"].find((m) =>
    MediaRecorder.isTypeSupported(m),
  );
  return new Promise((resolve, reject) => {
    const recorder = new MediaRecorder(stream, mime ? { mimeType: mime } : {}),
      chunks = [];
    let timer;
    recorder.ondataavailable = (e) => {
      if (e.data.size) chunks.push(e.data);
    };
    recorder.onerror = (e) => {
      clearTimeout(timer);
      reject(e.error || Error("録画できませんでした。"));
    };
    recorder.onstop = () => {
      clearTimeout(timer);
      resolve(new Blob(chunks, { type: recorder.mimeType }));
    };
    recorder.start();
    timer = setTimeout(() => {
      if (recorder.state !== "inactive") recorder.stop();
    }, 2000);
  });
}
