// Copies the web app into app/www for the native build (no service worker / PWA files needed there).
const fs=require('fs'),path=require('path');
const root=path.join(__dirname,'..'),out=path.join(root,'app','www');
fs.rmSync(out,{recursive:true,force:true});fs.mkdirSync(out,{recursive:true});
const cp=(a)=>{const s=path.join(root,a),d=path.join(out,a);const st=fs.statSync(s);
  if(st.isDirectory()){fs.mkdirSync(d,{recursive:true});for(const f of fs.readdirSync(s))cp(path.join(a,f))}else fs.copyFileSync(s,d)};
for(const a of ['index.html','icons','ocr'])cp(a);
console.log('www ready:',fs.readdirSync(out).join(', '));
