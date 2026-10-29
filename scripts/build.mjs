import {readFile,readdir,stat,mkdir,writeFile} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {gunzipSync} from 'node:zlib';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
await mkdir(resolve(root,'dist/data'),{recursive:true});
await writeFile(resolve(root,'dist/data/japan-municipalities.geojson'),gunzipSync(await readFile(resolve(root,'datasets/japan-municipalities.geojson.gz'))));
const html=await readFile(resolve(root,'dist/index.html'),'utf8');
for(const match of html.matchAll(/(?:src|href)="([^"#]+)"/g)){const file=match[1];if(/^(https?:|data:)/.test(file))continue;await stat(resolve(root,'dist',file))}
async function validateImports(folder){for(const name of await readdir(folder)){const file=resolve(folder,name),meta=await stat(file);if(meta.isDirectory())await validateImports(file);else if(name.endsWith('.js')){const content=await readFile(file,'utf8');for(const m of content.matchAll(/from\s+['"](\.\.?\/[^'"]+)['"]/g))await stat(resolve(dirname(file),m[1]))}}}
await validateImports(resolve(root,'dist'));
const boundaries=JSON.parse(await readFile(resolve(root,'dist/data/japan-municipalities.geojson'),'utf8'));
if(boundaries.features?.length!==1905)throw Error('Japan boundary dataset is incomplete.');
console.log('Static application ready in dist/. Entry points, modules and geographic data verified.');
