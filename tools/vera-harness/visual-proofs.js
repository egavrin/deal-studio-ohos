#!/usr/bin/env node
// Repeatable proof matrix. SVGs approximate native measurements; sharp rasterizes them.
'use strict'
const fs=require('node:fs'), path=require('node:path'), cp=require('node:child_process'), crypto=require('node:crypto')
const sharp=require('sharp')
const {loadVera}=require('./source-loader')
const C=loadVera('VeraCompiler'), V=loadVera('VeraInterpreter'), U=loadVera('VeraUi')
const dest=path.resolve(process.argv[2] || 'visual-proofs'), baselineRoot=process.argv[3]
if(!baselineRoot)throw Error('usage: node visual-proofs.js OUTPUT BASELINE_ETS_ROOT')
fs.mkdirSync(dest,{recursive:true})
const presets={clean:'counter',soft:'countdown',expressive:'counter',editorial:'reading',technical:'expense',playful:'habit'}
const manifest={revision:cp.execFileSync('git',['rev-parse','HEAD'],{cwd:path.join(__dirname,'../..'),encoding:'utf8'}).trim(),command:process.argv.join(' '),sourceHashes:{},approximation:'Host SVG layout uses estimated text widths; not native ArkUI screenshots.',images:[],sheets:[]}
for(const file of ['VeraTheme.ets','VeraUiCatalog.ets','VeraUi.ets','VeraCompiler.ets','VeraInterpreter.ets'])manifest.sourceHashes[file]=crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname,'../../entry/src/main/ets/vera',file))).digest('hex')
for(const relative of ['components/VeraPreview.ets','components/VeraLiveTree.ets'])manifest.sourceHashes[relative]=crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname,'../../entry/src/main/ets',relative))).digest('hex')
manifest.baselineThemeSha256=crypto.createHash('sha256').update(fs.readFileSync(path.join(baselineRoot,'vera/VeraTheme.ets'))).digest('hex')
function decode(source){ const m=new V.VirtualMachine(V.deserializeVbc2(C.compileVeraSource(source).vbc2),new U.UiHostEnvironment());return U.decodeVeraUi(m.execute('view',[m.execute('init')]))[0] }
function legacy(name){ const old=JSON.parse(fs.readFileSync(path.join(__dirname,'compatibility',name+'.json'),'utf8')); const m=new V.VirtualMachine(V.deserializeVbc2(old.bytecode),new U.UiHostEnvironment()); return U.decodeVeraUi(m.execute('view',[m.execute('init')]))[0] }
function widget(){return decode('import * as ui from "std/ui"\n@jsonable class AppState { count:int; }\nfunction init():AppState{return {count:7};}\nfunction change(state:AppState,value:int):AppState{return {count:state.count+value};}\nfunction view(state:AppState):ui.View{return ui.AppTheme("clean","",[ui.Column("compact",[ui.IntText("metric",state.count,"","",1),ui.ActionBar("default",[ui.Button("secondary","Subtract","change",-1,true),ui.Button("primary","Add","change",1,true)])])]);}')}
;(async()=>{
 for(const phase of ['baseline','candidate'])for(const dark of [false,true])for(const embedded of [false,true])for(const width of (embedded?[320]:[320,360,600])){
  const sheet=[]
  for(const [preset,fixture] of Object.entries(presets)){
   const file=path.join(__dirname,'examples',`visual-${fixture}.vera`),source=fs.readFileSync(file,'utf8')
   const input=embedded?widget():phase==='baseline'?legacy(fixture):decode(source)
   const label=`${phase} | ${preset} | ${dark?'dark':'light'} | ${width} vp${embedded?' | widget':''}`
   const id=`${phase}-${preset}-${dark?'dark':'light'}-${width}${embedded?'-widget':''}`
   const rawSvg=cp.execFileSync(process.execPath,[path.join(__dirname,'proof-sheet.js'),`--width=${width}`,`--preset=${preset}`,`--dark=${dark}`,`--embedded=${embedded}`,`--label=${label}`],{input:JSON.stringify(input),env:{...process.env,...(phase==='baseline'?{VERA_SOURCE_ROOT:baselineRoot}:{})}})
   const nativeHeight=Number(rawSvg.toString().match(/height="([0-9.]+)"/)[1])
   const caption=`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${nativeHeight+52}"><rect width="${width}" height="52" fill="#E2E8F0"/><text x="10" y="20" font-family="sans-serif" font-size="14" fill="#0F172A">${phase.toUpperCase()} / ${preset}</text><text x="10" y="40" font-family="sans-serif" font-size="13" fill="#334155">${dark?'Dark':'Light'} / ${width} vp / ${embedded?'Compact widget':'Full screen'}</text><g transform="translate(0,52)">${rawSvg.toString().replace(/<\?xml[^>]*>/,'')}</g></svg>`
   const svg=Buffer.from(caption)
   fs.writeFileSync(path.join(dest,id+'.svg'),svg);fs.writeFileSync(path.join(dest,id+'.tree.json'),JSON.stringify(input,null,2)+'\n')
   const png=await sharp(svg).png().toBuffer();fs.writeFileSync(path.join(dest,id+'.png'),png)
   const meta=await sharp(png).metadata();manifest.images.push({id,phase,preset,fixture:embedded?'compact-counter':fixture,dark,embedded,width,height:meta.height,svg:id+'.svg',png:id+'.png',tree:id+'.tree.json',sha256:crypto.createHash('sha256').update(png).digest('hex')});sheet.push({png,meta})
  }
  const colWidth=width+24,rowHeight=Math.max(...sheet.map(s=>s.meta.height))+24
  const png=await sharp({create:{width:colWidth*3,height:rowHeight*2,channels:4,background:'#CBD5E1'}}).composite(sheet.map((s,i)=>({input:s.png,left:(i%3)*colWidth+12,top:Math.floor(i/3)*rowHeight+12}))).png().toBuffer()
  const id=`sheet-${phase}-${dark?'dark':'light'}-${width}${embedded?'-widget':''}.png`;fs.writeFileSync(path.join(dest,id),png);manifest.sheets.push(id)
 }
 fs.writeFileSync(path.join(dest,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');console.log(`${manifest.images.length} proofs, ${manifest.sheets.length} sheets: ${dest}`)
})().catch(e=>{console.error(e);process.exitCode=1})
