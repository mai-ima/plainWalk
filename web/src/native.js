export const native = !!window.PlainWalkNative?.request;
export function nativeCall(action, payload = {}) {
  return native
    ? window.PlainWalkNative.request(action, payload)
    : Promise.reject(Error("この操作は iOS アプリで利用できます。"));
}
export function onNative(fn) {
  window.addEventListener("plainwalk-native", (e) => fn(e.detail));
}
export async function nativeDownload(blob, name) {
  const encoded = await new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).split(",")[1]);
    r.onerror = () => reject(r.error);
    r.readAsDataURL(blob);
  });
  return nativeCall("shareFile", { name, base64: encoded });
}
