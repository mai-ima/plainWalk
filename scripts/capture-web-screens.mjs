// Capture the implemented Web UI with isolated, explicitly synthetic data.
// Chromium mobile emulation is not physical iPhone/Safari verification.
import { chromium } from "playwright";
import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile, readdir, unlink } from "node:fs/promises";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));
const out = path.join(root, "artifacts/previews/web-all");
const port = Number(process.env.PW_SCREEN_PORT || 4176);
const base = process.env.PW_SCREEN_URL || `http://127.0.0.1:${port}`;
await mkdir(out, { recursive: true });
for(const name of await readdir(out))if(/^web-.*\.png$/.test(name)||name==="manifest.json")await unlink(path.join(out,name));
const photo = "data:image/png;base64," + (await readFile(path.join(root, "web/public/icon.png"))).toString("base64");
const video = "data:video/mp4;base64," + (await readFile(path.join(root, "tests/fixtures/clip.mp4"))).toString("base64");
const day = new Date().toISOString().slice(0, 10);
const start = Date.parse(`${day}T09:00:00Z`);
const points = [
  {lat:35.6800,lon:139.7600,t:start,accuracy:5,mode:"walking"},
  {lat:35.6808,lon:139.7600,t:start+120000,accuracy:5,mode:"walking"},
  {lat:35.6810,lon:139.7610,t:start+240000,accuracy:5,mode:"walking"},
  {lat:35.6815,lon:139.7613,t:start+360000,accuracy:5,mode:"walking"},
];
const walk = { id:"capture-walk",name:"検証用のさんぽ",start,end:start+360000,duration:360000,points,note:"合成データ。実際の歩行記録ではありません。" };
const library = {
  version:1,walks:[walk],flags:[{id:"capture-flag",name:"検証用の旗",lat:35.6815,lon:139.7613}],
  spots:[{id:"capture-photo",lat:35.6808,lon:139.7600,t:start+120000,photo,text:"検証用の写真ピン",emoji:"♡"},
    {id:"capture-video",lat:35.681,lon:139.761,t:start+240000,photo,video,text:"検証用の短い動画",emoji:"📷"}],
  notes:{[day]:{text:"検証用ノート\nこれは合成データです。",steps:1234,paper:"grid",font:"serif",stickers:"🌿",layout:[
    {id:"capture-note-photo",type:"photo",src:photo,x:230,y:460,width:230,ratio:1,rotation:-8},
    {id:"capture-sticker",type:"sticker",src:photo,x:490,y:610,width:170,ratio:1,rotation:12,finish:"plain"},
  ]}},
  notePages:{"capture-note-second":{id:"capture-note-second",day,text:"同じ日の2枚目\nページごとに内容を保存します。",paper:"lined",font:"sans",layout:[],stickers:"🌿"}},
  bookmarks:[{id:"capture-bookmark",name:"検証用の気になる場所",lat:35.6812,lon:139.7612}],
  doodles:[{id:"capture-doodle",name:"検証用の下絵",created:start,points:points.map(p=>({...p}))}],
  sharedMaps:[{id:"capture-shared",name:"検証用の共有白地図",walks:[{id:walk.id,points:points.map(({lat,lon})=>({lat,lon}))}]}],
};
const empty = {version:1,walks:[],spots:[],flags:[],notes:{},bookmarks:[],doodles:[],sharedMaps:[]};
const config = {theme:0,line:"solid",pin:"card",locationMark:"dot",cat:"black",dark:"light",beta:true,developerMode:true,accuracy:true,wake:false,goal:5000,reduce:true};
const manifest = {version:1,complete:false,generatedAt:new Date().toISOString(),platform:"web",engine:"Chromium mobile emulation",viewport:{width:393,height:852},fixture:"Synthetic local data. No user records or original-app screenshots.",screens:[],failures:[],limitations:[
  "Not a physical iPhone/Safari test; native Swift UI is a separate capture set.",
  "Screen routing uses the app's existing delegated data-action/data-* handlers; this is a visual inventory, not proof of every navigation gesture.",
  "OS file chooser, system sharing, real camera/microphone permission dialogs, native HealthKit/Live Activity/Watch are not simulated as working features.",
  "Browser select/time controls and all permission combinations are not an exhaustive OS-state inventory.",
  "Original-app screens that are not implemented are not counted as captured.",
]};
let server;
if (!process.env.PW_SCREEN_URL) {
  server=spawn("python3",["-m","http.server",String(port),"--directory",path.join(root,"dist")],{stdio:"ignore"});
  for(let i=0;i<40;i++){try{if((await fetch(base)).ok)break;}catch{}await new Promise(r=>setTimeout(r,100));}
}
const browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH||(existsSync("/usr/bin/chromium")?"/usr/bin/chromium":undefined),args:["--no-sandbox"]});
// Invoke the same event route that an app button uses, without exposing module internals.
async function dispatch(page,dataset){
  await page.evaluate(d=>{const b=document.createElement("button");Object.assign(b.dataset,d);document.body.append(b);b.click();b.remove();},dataset);
  await page.waitForTimeout(160);
}
const action=(p,name)=>dispatch(p,{action:name});
const tab=(p,name)=>dispatch(p,{tab:name});
async function decodeAndPauseVideo(page,selector){
  await page.locator(selector).evaluate(node=>new Promise((resolve,reject)=>{
    const start=node.currentTime;let settled=false;
    const finish=error=>{
      if(settled)return;settled=true;clearTimeout(timer);
      node.removeEventListener("timeupdate",advanced);node.removeEventListener("error",failed);node.pause();
      error?reject(error):resolve();
    };
    const failed=()=>finish(Error(`Video decoder failed: ${node.error?.code??"unknown"} ${node.error?.message??"playback rejected"}`));
    const advanced=()=>{
      if(node.readyState<2||node.currentTime<=start+0.05)return;
      if(node.duration!==2||node.videoWidth!==320||node.videoHeight!==240){finish(Error(`Unexpected video fixture: ${node.duration}s ${node.videoWidth}x${node.videoHeight}`));return;}
      finish();
    };
    const timer=setTimeout(()=>finish(Error(`Video decode/playback timed out: readyState=${node.readyState}, currentTime=${node.currentTime}`)),8000);
    node.addEventListener("timeupdate",advanced);node.addEventListener("error",failed);node.muted=true;
    if(node.error){failed();return;}
    try{node.play().then(advanced,failed);}catch{failed();}
  }));
}
async function shot(page,key,title,category,state,{scroll=false}={}){
  await page.locator("#toast").evaluate(e=>e.hidden=true).catch(()=>{});
  await page.evaluate(()=>document.fonts.ready);
  await page.waitForTimeout(120);
  const save=async(suffix,index,scrollTop)=>{
    await page.evaluate(()=>{if(document.activeElement instanceof HTMLElement)document.activeElement.blur();});
    const file=`web-${key}${suffix}.png`;
    await page.screenshot({path:path.join(out,file),animations:"disabled"});
    const headings=await page.locator("h1:visible,h2:visible").allTextContents();
    manifest.screens.push({key:key+suffix,title,category,state,path:file,part:index,scrollTop,sourceRoute:key,visibleHeadings:headings});
  };
  if(scroll)await page.evaluate(()=>{
    const el=!document.querySelector("#overlay").hidden?document.querySelector("#sheet"):document.querySelector("#contentPage");el.scrollTop=0;
  });
  await page.waitForTimeout(70);
  await save("",1,0);
  if(!scroll)return;
  const info=await page.evaluate(()=>{
    const el=!document.querySelector("#overlay").hidden?document.querySelector("#sheet"):document.querySelector("#contentPage");
    return {selector:el.id,max:el.scrollHeight-el.clientHeight,step:Math.max(250,el.clientHeight-100)};
  });
  let index=1;
  for(let y=info.step;y<info.max+info.step;y+=info.step){
    const top=Math.min(y,info.max);if(top<=0)break;
    await page.locator("#"+info.selector).evaluate((e,t)=>{e.scrollTop=t;},top);
    await page.waitForTimeout(90);await save(`-part${++index}`,index,top);
    if(top===info.max)break;
  }
}
const tasks=[];
function add(key,title,category,run,{data=library,active=null,dark=false,scroll=false,state="populated"}={}){tasks.push({key,title,category,run,data,active,dark,scroll,state});}
const A=(key,title,name,options={})=>add(key,title,options.category||"その他",p=>action(p,name),options);
add("map","マイマップ","地図",async p=>{await action(p,"allMap");await action(p,"locate");});
add("map-empty","マイマップ・初期状態","地図",async()=>{},{data:empty,state:"empty"});
add("map-dark","マイマップ・ダーク","地図",p=>action(p,"allMap"),{dark:true});
add("answer","答え合わせマップ","地図",async p=>{await action(p,"allMap");await action(p,"answer");await p.waitForTimeout(700);});
add("answer-tilt","答え合わせ・平面表示（Webの3Dは未対応）","地図",async p=>{await action(p,"allMap");await action(p,"answer");await action(p,"tilt");await p.waitForTimeout(500);},{state:"flat-fallback-not-3D"});
A("menu","メニュー","menu",{category:"地図",scroll:true});
A("layers","地図レイヤー・全区間","layers",{category:"地図",scroll:true});
A("record-start","記録を始める","recordOptions",{category:"記録",data:empty,state:"before-recording"});
const active={...walk,id:"capture-active",end:undefined,name:undefined,pausedMs:0,pauseAt:start+360000};
A("record-paused","記録・一時停止中","recordOptions",{category:"記録",active,state:"paused synthetic checkpoint"});
A("record-discard","記録を破棄・確認","discardConfirm",{category:"記録",active,state:"confirmation"});
add("record-recovery","記録の復旧","記録",async()=>{},{active,state:"synthetic paused checkpoint recovery"});
add("records","記録・カレンダー","記録",p=>tab(p,"records"),{scroll:true});
add("records-empty","記録・空状態","記録",p=>tab(p,"records"),{data:empty,state:"empty",scroll:true});
add("record-day","1日の記録","記録",async p=>{await tab(p,"records");await dispatch(p,{day});});
A("record-week","今週のふりかえり","weeklyReview",{category:"記録",scroll:true});
A("statistics","歩行の統計","stats",{category:"記録",scroll:true});
A("steps","歩数と目標","steps",{category:"記録",scroll:true});
add("walk-detail","さんぽ詳細","記録",async p=>{await tab(p,"records");await dispatch(p,{walk:walk.id});},{scroll:true});
add("walk-delete","さんぽ削除・確認","記録",p=>dispatch(p,{deleteWalk:walk.id}),{state:"confirmation"});
add("walk-map","さんぽを白地図で見る","記録",p=>dispatch(p,{mapWalk:walk.id}));
add("walk-editor","軌跡を手で修正","編集",p=>dispatch(p,{editWalk:walk.id}));
add("walk-editor-point","軌跡の点・編集操作","編集",async p=>{await dispatch(p,{editWalk:walk.id});await p.locator('[data-edit-point="1"]').tap();});
A("replay-all","地図の成長を再生","replay",{category:"記録"});
add("replay-walk","1回のさんぽを再生","記録",p=>dispatch(p,{replayWalk:walk.id}));
add("share-card","さんぽの共有カード","記録",p=>dispatch(p,{shareWalk:walk.id}),{scroll:true});
add("profile","プロフィール","プロフィール",p=>tab(p,"profile"),{scroll:true});
for(const [key,title,act] of [["spots","ここいいな","spots"],["stickers","ステッカー","stickers"],["badges","エリアバッジ","badges"],["doodles","らくがき","doodles"],["shared","共有の白地図","sharedMaps"],["bookmarks","気になる場所","bookmarks"],["flags","目的地の旗","flags"]]){
  A(key,title,act,{category:"コレクション",scroll:true});
  A(key+"-empty",title+"・空状態",act,{category:"コレクション",data:empty,state:"empty",scroll:true});
}
add("badge-detail","エリアバッジ詳細","コレクション",async p=>{await action(p,"badges");await p.locator("[data-area]").first().waitFor();await p.locator("[data-area]").first().click();},{scroll:true});
add("photo-detail","写真ピン詳細","コレクション",p=>dispatch(p,{spot:"capture-photo"}),{scroll:true});
add("video-detail","短い動画ピン詳細","コレクション",async p=>{await dispatch(p,{spot:"capture-video"});await decodeAndPauseVideo(p,"#sheetBody video");},{scroll:true,state:"decoded-paused synthetic two-second MP4 fixture; real playback advanced"});
add("photo-delete","写真ピン削除・確認","コレクション",p=>dispatch(p,{spotDelete:"capture-photo"}),{state:"confirmation"});
add("sticker-detail","ステッカー詳細","コレクション",p=>dispatch(p,{stickerItem:"capture-sticker"}),{scroll:true});
A("sticker-exchange","ステッカーをあげる・対応範囲","stickerExchange",{category:"コレクション",state:"availability explanation"});
add("bookmark-detail","気になる場所の詳細","コレクション",p=>dispatch(p,{bookmark:"capture-bookmark"}));
add("doodle-detail","らくがきの詳細","コレクション",p=>dispatch(p,{doodle:"capture-doodle"}));
A("doodle-editor","らくがきを描く","doodleStart",{category:"編集"});
A("shared-create","共有の紙を作る","sharedCreate",{category:"コレクション",scroll:true});
add("shared-detail","共有の紙の詳細","コレクション",p=>dispatch(p,{sharedMap:"capture-shared"}));
add("flag-detail","目的地の旗の詳細","コレクション",p=>dispatch(p,{flagDetail:"capture-flag"}),{scroll:true});
A("flag-create","目的地の旗を追加","flagAdd",{category:"編集",scroll:true});
add("bookmark-create","気になる場所を保存","編集",async p=>{await action(p,"bookmarkPick");await p.locator("#mapViewport").tap({position:{x:180,y:280}});});
A("photo-import","写真を取り込む・場所の選択","photoImport",{category:"写真",scroll:true});
add("photo-capture","写真を残す","写真",async p=>{await action(p,"photoImport");await action(p,"spotPick");await p.locator("#mapViewport").tap({position:{x:180,y:280}});},{scroll:true});
add("video-capture","短い動画を残す","写真",async p=>{await action(p,"photoImport");await action(p,"spotPick");await p.locator("#mapViewport").tap({position:{x:180,y:280}});await dispatch(p,{spotMode:"video"});},{scroll:true});
A("note","ノート・配置済み","notes",{category:"ノート",scroll:true});
A("note-library","日付ごとのノート一覧","noteLibrary",{category:"ノート",scroll:true});
A("note-empty","ノート・初期状態","notes",{category:"ノート",data:empty,state:"empty",scroll:true});
add("note-second-page","同じ日の2枚目のノート","ノート",async p=>{await action(p,"notes");await p.locator("#notePage").selectOption("capture-note-second");await p.waitForFunction(()=>document.querySelector("#dailyNote")?.value.startsWith("同じ日の2枚目"));},{scroll:true,state:"synthetic additional page selected"});
add("note-delete-confirm","ノートのページ削除・確認","ノート",async p=>{await action(p,"notes");await action(p,"noteDeletePage");},{state:"confirmation"});
add("note-photo-picker","ノートの写真選択","ノート",async p=>{await action(p,"notes");await action(p,"notePhoto");},{scroll:true});
add("note-sticker-picker","ノートの切り抜き素材選択","ノート",async p=>{await action(p,"notes");await action(p,"noteCutout");},{scroll:true});
add("note-cutout","ノートの写真切り抜き","ノート",async p=>{await action(p,"notes");await action(p,"noteCutout");await p.locator('[data-note-photo="capture-photo"]').click();},{scroll:true});
add("note-item-controls","ノート・素材の調整","ノート",async p=>{await action(p,"notes");const c=p.locator("#noteCanvas");await c.scrollIntoViewIfNeeded();const box=await c.boundingBox();await c.tap({position:{x:box.width*230/720,y:box.height*460/960}});},{scroll:true});
A("settings","設定・全区間","settings",{category:"設定",scroll:true});
A("lut","LUT・案内","lutSettings",{category:"設定",state:"no LUT imported"});
A("health","ヘルスケア・入口","healthImport",{category:"設定",state:"native API unavailable in Web"});
A("home-place","自宅・対応範囲","homePlace",{category:"設定",state:"unsupported explanation"});
A("work-place","職場・対応範囲","workPlace",{category:"設定",state:"unsupported explanation"});
A("add-place","よく行く場所・対応範囲","addPlace",{category:"設定",state:"unsupported explanation"});
add("movement-policy","動き出したとき・対応範囲","設定",p=>dispatch(p,{movementPolicy:"notify"}),{state:"unsupported explanation"});
A("about","このWeb版について","about",{category:"設定",scroll:true});
A("limitations","iOSとWebの対応範囲","limitations",{category:"設定",scroll:true});
A("diagnostics","GPSの診断","diagnostics",{category:"開発者",scroll:true});
A("storage","保存領域","storage",{category:"開発者",scroll:true});
A("developer","開発者向け・全区間","developer",{category:"開発者",scroll:true});
add("developer-storage-test","開発者・保存テスト結果","開発者",async p=>{await action(p,"developer");await action(p,"devStorage");},{scroll:true});
A("reset-confirm","データのリセット・確認","resetData",{category:"設定",state:"confirmation only"});
A("demo","体験モード","demo",{category:"地図",state:"demo; no saved walk"});
add("track-import","GPX取り込み確認","取り込み",async p=>{await p.locator("#importFile").setInputFiles({name:"検証用.gpx",mimeType:"application/gpx+xml",buffer:Buffer.from(`<gpx><trk><trkseg>${points.map(p=>`<trkpt lat="${p.lat}" lon="${p.lon}"><time>${new Date(p.t).toISOString()}</time></trkpt>`).join("")}</trkseg></trk></gpx>`)});},{scroll:true,state:"confirmation only"});
add("backup-import","バックアップ取り込み確認","取り込み",async p=>{await p.locator("#importFile").setInputFiles({name:"検証用バックアップ.json",mimeType:"application/json",buffer:Buffer.from(JSON.stringify(library))});},{scroll:true,state:"confirmation only"});
add("note-route","ノート・道を貼る","ノート",async p=>{await action(p,"notes");await action(p,"noteRoute");},{scroll:true,state:"synthetic route added to draft"});
add("photo-selected","写真を残す・画像選択済み","写真",async p=>{await action(p,"photoImport");await action(p,"spotPick");await p.locator("#mapViewport").tap({position:{x:180,y:280}});await p.locator("#spotPhoto").setInputFiles(path.join(root,"web/public/icon.png"));await p.locator("#spotPreview").waitFor({state:"visible"});},{scroll:true,state:"synthetic app icon; no EXIF"});
add("photo-lut-import","写真・カスタムLUTの読み込み","写真",async p=>{await action(p,"photoImport");await action(p,"spotPick");await p.locator("#mapViewport").tap({position:{x:180,y:280}});await p.locator(".film-advanced summary").click();},{scroll:true,state:"expanded import controls; no file chooser"});
add("video-selected","短い動画を残す・選択済み","写真",async p=>{await action(p,"photoImport");await action(p,"spotPick");await p.locator("#mapViewport").tap({position:{x:180,y:280}});await p.locator("#spotVideo").setInputFiles(path.join(root,"tests/fixtures/clip.mp4"));await p.locator("#spotVideoPreview").waitFor({state:"visible",timeout:20000});await decodeAndPauseVideo(p,"#spotVideoPreview");},{scroll:true,state:"decoded-paused synthetic two-second MP4 fixture; real playback advanced"});
add("record-too-short","道がない記録の保存案内","記録",p=>action(p,"finish"),{active:{...active,points:[]},state:"empty synthetic checkpoint"});
add("badges-load-error","エリアバッジ・読み込みエラー","コレクション",async p=>{await p.route("**/data/japan-municipalities.geojson",route=>route.abort());await action(p,"badges");await p.waitForFunction(()=>!document.querySelector("#areaProgress"));},{state:"intentional boundary request failure"});
try{
  for(const t of tasks){
    const ctx=await browser.newContext({viewport:{width:393,height:852},isMobile:true,hasTouch:true,deviceScaleFactor:1,timezoneId:"UTC",locale:"ja-JP",colorScheme:t.dark?"dark":"light",acceptDownloads:true,permissions:["geolocation"],geolocation:{latitude:35.6808,longitude:139.7600,accuracy:5},serviceWorkers:"block"});
    const page=await ctx.newPage();page.setDefaultTimeout(6000);const errors=[];page.on("pageerror",e=>errors.push(e.message));
    try{
      await page.goto(base);await page.locator("#recordButton").waitFor();
      await page.evaluate(async ({data,config,active})=>{await new Promise((resolve,reject)=>{const r=indexedDB.open("plainwalk-web",1);r.onsuccess=()=>{const db=r.result,t=db.transaction("data","readwrite"),s=t.objectStore("data");s.put(data,"library");s.put(config,"config");s.put(active,"active");t.oncomplete=()=>{db.close();resolve();};t.onerror=()=>reject(t.error);};r.onerror=()=>reject(r.error);});},{data:t.data,config:{...config,dark:t.dark?"dark":"light"},active:t.active});
      await page.reload();await page.locator("#recordButton").waitFor();await page.waitForTimeout(150);
      if(!t.active)await action(page,"close");
      await t.run(page);
      if(t.key.startsWith("badges")){await page.waitForFunction(()=>!document.querySelector("#areaProgress"));}
      if(errors.length)throw Error(errors.join("; "));
      await shot(page,t.key,t.title,t.category,t.state,{scroll:t.scroll});
      console.log("captured",t.key);
    }catch(e){manifest.failures.push({key:t.key,title:t.title,error:e.message});console.error("NOT CAPTURED",t.key,e.message);}
    finally{await ctx.close();await writeFile(path.join(out,"manifest.json"),JSON.stringify(manifest,null,2));}
  }
}finally{await browser.close();server?.kill();}
manifest.complete=manifest.failures.length===0&&tasks.every(t=>manifest.screens.some(s=>s.sourceRoute===t.key));
manifest.routeStateCount=tasks.length;manifest.imageCount=manifest.screens.length;
await writeFile(path.join(out,"manifest.json"),JSON.stringify(manifest,null,2));
console.log(JSON.stringify({screens:manifest.screens.length,routes:tasks.length,failures:manifest.failures.length,manifest:path.join(out,"manifest.json")}));
if(manifest.failures.length)process.exitCode=1;
