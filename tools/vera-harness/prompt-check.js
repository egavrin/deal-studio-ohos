const fs = require('node:fs');
const crypto = require('node:crypto');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const ts = (process.env.VERA_TYPESCRIPT_PATH ? require(process.env.VERA_TYPESCRIPT_PATH) : require('typescript'));
const root = path.resolve(process.argv[2] || path.join(__dirname, '../..'));
const output = path.resolve(process.argv[3] || 'prompt-verification.json');
const base = path.join(root, 'entry/src/main/ets/vera');
const requests = [], responses = [], cache = new Map(), checks = [];
const http = {RequestMethod:{POST:'POST'}, createHttp(){
  let callback;
  return {on(event, fn){if(event==='dataReceive')callback=fn},off(){},destroy(){},
    async requestInStream(url,options){
      requests.push(JSON.parse(options.extraData));
      assert(responses.length, 'Missing deterministic HTTP response');
      const response=responses.shift(); const content=typeof response==='string'?response:response.content; const finish=typeof response==='string'?'stop':response.finish;
      const delta=typeof response==='object'&&response.toolCalls ? {tool_calls:response.toolCalls} : {content};
      const data='data: '+JSON.stringify({choices:[{delta,finish_reason:typeof response==='object'&&response.toolCalls?'tool_calls':finish}],usage:{prompt_tokens:1,completion_tokens:1}})+'\n\ndata: [DONE]\n\n';
      const bytes=Buffer.from(data); callback(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.length));
      return 200;
    }
  };
}};
function load(file){
  file=path.resolve(file); if(cache.has(file))return cache.get(file).exports;
  let source=fs.readFileSync(file,'utf8');
  const mod={exports:{}}; cache.set(file,mod);
  const compiled=ts.transpileModule(source,{fileName:file.replace(/\.ets$/,'.ts'),compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020,esModuleInterop:true},reportDiagnostics:true});
  assert.equal((compiled.diagnostics||[]).filter(x=>x.category===ts.DiagnosticCategory.Error).length,0,file+' TypeScript syntax');
  const requireLocal=name=>{
    if(name==='@ohos.net.http')return http;
    if(name==='@ohos.util')return {TextDecoder:{create:()=>({decodeToString:bytes=>new TextDecoder().decode(bytes)})}};
    if(name.startsWith('@ohos.')||name==='libllama.so')return {};
    if(name.startsWith('.'))return load(path.join(path.dirname(file),name+'.ets'));
    throw Error('Unexpected dependency '+name);
  };
  new Function('require','module','exports',compiled.outputText)(requireLocal,mod,mod.exports);
  return mod.exports;
}
function read(rel){return fs.readFileSync(path.join(root,rel),'utf8')}
function run(name,fn){try{const observed=fn();checks.push({name,status:'PASS',observed});return observed}catch(e){checks.push({name,status:'FAIL',observed:e.message});}}
async function runAsync(name,fn){try{const observed=await fn();checks.push({name,status:'PASS',observed});}catch(e){checks.push({name,status:'FAIL',observed:e.message});}}
const skill=read('entry/src/main/resources/rawfile/vera-skill.txt');
const widget=read('entry/src/main/resources/rawfile/vera-widget.txt');
const compiler=load(path.join(base,'VeraCompiler.ets'));
const runtime=load(path.join(base,'VeraInterpreter.ets'));
const ui=load(path.join(base,'VeraUi.ets'));
const catalog=load(path.join(base,'VeraUiCatalog.ets'));
const selection=load(path.join(base,'VeraUiSelect.ets'));
const example=skill.slice(skill.lastIndexOf('\nimport * as ui from "std/ui"')+1).trim();
let machine,host,state,tree;
function render(current){host.effectsAllowed=false;const result=ui.decodeVeraUi(machine.execute('view',[current]));return result;}
function countNodes(nodes){return nodes.reduce((sum,n)=>sum+1+countNodes(n.children),0)}
run('Prompt template assembly: full, selected, widget',()=>{
  for(const [name,note,selected] of [['full','',null],['selected',selection.UI_TOOL_NOTE,new Set(['IntField'])],['widget','',null]]){
    let text=skill.replace('{{UI_CATALOG}}',catalog.describeCatalogForPrompt(selected)).replace('{{UI_TOOL_NOTE}}\n',note)+(name==='widget'?widget:'');
    assert(!/\{\{UI_/.test(text),'Unresolved placeholder in '+name);
    assert(text.includes('ui.AppTheme'),'Root theme absent');
  }
  return {templateCharacters:skill.length,widgetCharacters:widget.length,modes:3};
});
run('Compile the complete prompt example',()=>{
  const compiled=compiler.compileVeraSource(example);
  host=new ui.UiHostEnvironment();machine=new runtime.VirtualMachine(runtime.deserializeVbc2(compiled.vbc2),host);
  state=machine.execute('init');return {bytecodeBytes:compiled.vbc2.length};
});
run('Render initial state through real VM and UI decoder',()=>{
  const snapshot=JSON.stringify(runtime.encodeRuntimeValue(state));tree=render(state);
  assert.equal(tree[0].kind,'apptheme');assert(countNodes(tree)<=80);
  assert.equal(JSON.stringify(runtime.encodeRuntimeValue(state)),snapshot);
  return {root:tree[0].kind,nodes:countNodes(tree),pendingEffects:host.pendingEffects.length};
});
run('Edit input and add entry without mutating earlier state',()=>{
  const before=JSON.stringify(runtime.encodeRuntimeValue(state));
  host.effectsAllowed=true;
  let adjusted=machine.execute('setSize',[state,new runtime.VeraIntValue(30)]);
  let added=machine.execute('add',[adjusted,new runtime.VeraIntValue(0)]);
  assert.equal(JSON.stringify(runtime.encodeRuntimeValue(state)),before,'Add handler mutated an earlier state');
  const raw=runtime.encodeRuntimeValue(added); assert(raw);
  assert.equal(added.fields.get('log').elements.length,1);
  const first=JSON.stringify(runtime.encodeRuntimeValue(added));
  let addedAgain=machine.execute('add',[added,new runtime.VeraIntValue(0)]);
  assert.equal(JSON.stringify(runtime.encodeRuntimeValue(added)),first,'Second add mutated prior state');
  assert.equal(addedAgain.fields.get('log').elements.length,2);
  state=addedAgain;return {entries:2};
});
run('Persist, restore and render populated state',()=>{
  const encoded=JSON.parse(JSON.stringify(runtime.encodeRuntimeValue(state)));
  const restored=runtime.decodeRuntimeValue(encoded);
  const first=render(restored), second=render(restored);
  assert.deepEqual(first,second);assert(countNodes(first)<=80);
  return {root:first[0].kind,nodes:countNodes(first)};
});
run('Intent callback classification through compile, dispatch and render',()=>{
  const test=skill.match(/let failed: boolean = [^\n]+/);assert(test,'Intent result classification example missing');
  const source='import * as ui from "std/ui"\nimport * as strings from "std/strings"\n@jsonable class AppState { answer: string; failed: boolean; }\nfunction init(): AppState { return {answer: "Pending", failed: false}; }\nfunction onAnswer(state: AppState, value: string): AppState { '+test[0]+' return {answer: value, failed: failed}; }\nfunction view(state: AppState): ui.View { return ui.AppTheme("clean", "", [ui.Text("body", state.answer), ui.Text("caption", ui.booleanToString(state.failed))]); }';
  const h=new ui.UiHostEnvironment();const m=new runtime.VirtualMachine(runtime.deserializeVbc2(compiler.compileVeraSource(source).vbc2),h);
  const cases=[['ok',false],['{"accepted":true}',false],['declined by the person',true],['declined code=1',true],['error 5: unavailable',true]];
  for(const [answer,expected] of cases){let st=m.execute('onAnswer',[m.execute('init'),new runtime.VeraStringValue(answer)]);const nodes=ui.decodeVeraUi(m.execute('view',[st]));assert.equal(nodes[0].children[0].text,answer);assert.equal(nodes[0].children[1].text,String(expected));}
  return {cases:cases.length,rawAnswersPreserved:true};
});
run('Widget currency helper handles cents and negative amounts',()=>{
  const begin=widget.indexOf('function money(');assert(begin>=0,'Currency helper missing');
  let open=widget.indexOf('{',begin),depth=1,end=open+1;
  while(depth>0&&end<widget.length){if(widget[end]==='{')depth++;if(widget[end]==='}')depth--;end++;}
  const helper=widget.slice(begin,end);
  const source='import * as ui from "std/ui"\n'+helper+'\n@jsonable class AppState { cents: int; }\nfunction init(): AppState { return {cents: 0}; }\nfunction set(state: AppState, value: int): AppState { return {cents: value}; }\nfunction view(state: AppState): ui.View { return ui.AppTheme("technical", "", [ui.Text("body", money(state.cents))]); }';
  const h=new ui.UiHostEnvironment();const m=new runtime.VirtualMachine(runtime.deserializeVbc2(compiler.compileVeraSource(source).vbc2),h);
  const cases=[[0,'$0.00'],[2248,'$22.48'],[18740,'$187.40'],[-1,'-$0.01'],[-105,'-$1.05'],[2147483647,'$21474836.47'],[-2147483648,'-$21474836.48']];
  for(const [input,expected] of cases){let st=m.execute('set',[m.execute('init'),new runtime.VeraIntValue(input)]);const nodes=ui.decodeVeraUi(m.execute('view',[st]));assert.equal(nodes[0].children[0].text,expected,'Currency for '+input);}
  return {cases:cases.length};
});
(async()=>{
  const llama=load(path.join(base,'LlamaEngine.ets'));
  const deep=load(path.join(base,'DeepSeekEngine.ets'));
  const chat=load(path.join(base,'VeraChat.ets'));
  const settings=load(path.join(base,'SettingsStore.ets')).settings;
  settings.getApiKey=()=> 'host-test-key';settings.hasApiKey=()=>true;
  settings.getModel=()=> 'test-model';settings.getBaseUrl=()=> 'https://host-test.invalid';
  function assertUniform(sent=requests){
    assert(sent.length>0,'No generation request');
    for(const body of sent){
      assert.equal(body.thinking.type,'enabled','Reasoning must be enabled');
      assert.equal(body.max_tokens,32768,'Uniform output-token limit');
      assert.equal(body.temperature,0.2,'Generation temperature preserved');
    }
  }
  function reset(){requests.length=0;responses.length=0;}
  function method(src,name){
    const start=src.search(new RegExp('private (?:async )?'+name+'\\('));assert(start>=0,'Method '+name);
    const scanner=ts.createScanner(ts.ScriptTarget.Latest,true,ts.LanguageVariant.Standard,src.slice(start));
    let depth=0,opened=false;
    while(scanner.scan()!==ts.SyntaxKind.EndOfFileToken){
      if(scanner.getToken()===ts.SyntaxKind.OpenBraceToken){opened=true;depth++;}
      if(scanner.getToken()===ts.SyntaxKind.CloseBraceToken&&--depth===0&&opened)return src.slice(start,start+scanner.getTextPos());
    }
    throw Error('Unclosed method '+name);
  }
  function page(){
    const src=read('entry/src/main/ets/pages/GeneratePage.ets');
    const prefix=src.slice(0,src.indexOf('@Entry')).replace(/^import .*$/gm,'');
    const code=prefix+'\nclass Controller { '+['callModel','runAttempt','doRefine'].map(n=>method(src,n)).join('\n')+' } module.exports=Controller;';
    const compiled=ts.transpileModule(code,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020},reportDiagnostics:true});
    assert.equal((compiled.diagnostics||[]).filter(d=>d.category===ts.DiagnosticCategory.Error).length,0,'Extracted generation controller syntax');
    const globals={UI_SELECT_FULL:selection.UI_SELECT_FULL,UI_SELECT_PROMPT:selection.UI_SELECT_PROMPT,settings,deepseek:deep.deepseek,DEEPSEEK_GENERATION_MAX_TOKENS:deep.DEEPSEEK_GENERATION_MAX_TOKENS,
      GenerateRequest:llama.GenerateRequest,compileVeraSource:compiler.compileVeraSource,CompileError:compiler.CompileError,
      engine:{generate(request){return {text:example,inputTokens:1,outputTokens:1,request}}}};
    const mod={exports:{}};new Function('module',...Object.keys(globals),compiled.outputText)(mod,...Object.values(globals));
    const c=new mod.exports();
    Object.assign(c,{mode:'deepseek',attempt:1,systemPrompt:skill,uiSelected:[],grammar:'',previousSource:'',failedSource:'',
      attempts:[],compiledVbc2:'',cancelRequested:false,genStartTime:Date.now(),generatedSource:'',generating:true});
    c.addToProgram=()=>{};c.currentRun=()=>null;c.startRun=()=>{};
    c.startAttemptOne=ask=>{c.pending=c.runAttempt(ask,'');};
    return c;
  }
  function compilerError(source){try{compiler.compileVeraSource(source);throw Error('Fixture compiled unexpectedly');}catch(e){assert(e instanceof compiler.CompileError);return e.message;}}
  await runAsync('Shared generation token limit is 32768',async()=>{
    assert.equal(deep.DEEPSEEK_GENERATION_MAX_TOKENS,32768);return {maxTokens:32768};
  });
  await runAsync('Generate screen first candidate compiles with uniform settings and metrics',async()=>{
    reset();responses.push(example);const c=page();await c.runAttempt('An editable amount log.','');
    assert.equal(c.compiled,true);assert.equal(c.compiledSource,example);assert.equal(requests.length,1);assertUniform();
    assert.equal(c.attempts[0].thinking,true);assert.equal(c.attempts[0].success,true);
    return {attempts:1,thinking:requests[0].thinking.type,maxTokens:requests[0].max_tokens,metricsThinking:c.attempts[0].thinking};
  });
  await runAsync('Generate screen compiler retry retains exact source and diagnostics',async()=>{
    reset();const broken='function broken(';const diagnostic=compilerError(broken);responses.push(broken,example);
    const c=page();await c.runAttempt('An editable amount log.','');assert.equal(c.compiled,true);assert.equal(c.attempt,2);assertUniform();
    assert.equal(requests[1].messages[1].content,broken);assert(requests[1].messages.at(-1).content.includes(diagnostic));
    assert(c.attempts.every(m=>m.thinking));assert.equal(c.attempts[0].success,false);assert.equal(c.attempts[1].success,true);
    return {attempts:2,exactFailedSource:true,exactCompilerDiagnostics:true,allMetricsThinking:true};
  });
  await runAsync('Generate screen refinement first attempt retains current compiled source',async()=>{
    reset();responses.push(example);const c=page();c.compiledSource=example;c.refinePrompt='Change the amount to 30.';c.doRefine();await c.pending;
    assert.equal(c.compiled,true);assertUniform();assert.equal(requests[0].messages[1].content,example);
    assert(requests[0].messages.at(-1).content.includes(c.refinePrompt||'Change the amount to 30.'));
    assert.equal(c.attempts[0].thinking,true);return {attempts:1,currentSourcePreserved:true};
  });
  await runAsync('Generate screen all three compiler attempts use uniform settings',async()=>{
    reset();responses.push('function broken(','function broken(','function broken(');const c=page();await c.runAttempt('An amount log.','');
    assert.equal(c.attempts.length,3);assert.equal(c.generating,false);assert(c.compileErrors.length>0);assertUniform();
    return {attempts:3,terminalFailure:true};
  });
  await runAsync('Widget first candidate compiles with uniform settings',async()=>{
    reset();responses.push(example);const result=await chat.buildMiniApp(skill+widget,'An editable amount log.',()=>{});
    assert.equal(result.error,'');assert.equal(result.attempts,1);assert.equal(result.source,example);assertUniform();
    return {attempts:1,thinking:requests[0].thinking.type,maxTokens:requests[0].max_tokens};
  });
  await runAsync('Widget all three compiler attempts use uniform settings',async()=>{
    reset();responses.push('function broken(','function broken(','function broken(');
    const result=await chat.buildMiniApp(skill+widget,'An amount log.',()=>{});assert.equal(result.attempts,3);assert(result.error.length>0);assertUniform();
    return {attempts:3,terminalFailure:true};
  });
  const lookup={toolCalls:[{index:0,id:'lookup',type:'function',function:{name:'find_sdk_function',arguments:'{"need":"battery level"}'}}]};
  load(path.join(base,'VeraSdkEmbeddingCache.ets')).findSdkFunctionByEmbedding=async()=>[];
  await runAsync('Generate screen tool continuation retains uniform settings',async()=>{
    reset();responses.push(lookup,example);const c=page();await c.runAttempt('An editable amount log.','');
    assert.equal(c.compiled,true);assert.equal(requests.length,2);assertUniform();
    assert(requests[1].messages.some(m=>m.role==='tool'));return {requests:2,toolResultDelivered:true};
  });
  await runAsync('Widget forced final tool round retains uniform settings',async()=>{
    reset();responses.push(lookup,lookup,lookup,lookup,example);
    const result=await chat.buildMiniApp(skill+widget,'An editable amount log.',()=>{});assert.equal(result.error,'');assert.equal(result.attempts,1);
    assert.equal(requests.length,5);assertUniform();assert.equal(requests.at(-1).tools,undefined);
    return {requests:5,finalToolsDisabled:true};
  });
  await runAsync('Local generation keeps its original token budget',async()=>{
    reset();const c=page();c.mode='local';const request=new llama.GenerateRequest();request.maxTokens=2048;
    const result=await c.callModel(request,()=>{});assert.equal(result.request.maxTokens,2048);assert.equal(requests.length,0);
    return {maxTokens:2048,httpRequests:0};
  });
  await runAsync('Cloud and local refinement transport preserve source and request',async()=>{
    const request=new llama.GenerateRequest();request.systemPrompt=skill;request.previousSource=example;request.userPrompt='Change the amount to 30.';
    responses.push(example);const result=await deep.deepseek.generate(request,()=>{});
    const sent=requests.at(-1).messages;
    assert.equal(sent[0].role,'system');assert.equal(sent[1].content,example);assert(sent[2].content.includes(request.userPrompt));
    assert.equal(result.text,example);
    const local=new llama.LlamaEngine().buildPrompt(request);
    assert(local.includes(example));assert(local.includes(request.userPrompt));return {providers:2,sourcePreserved:true};
  });
  await runAsync('Widget compile-repair workflow uses failed source and original goal',async()=>{
    requests.length=0;responses.push('function broken(',example);
    const result=await chat.buildMiniApp(skill+widget,'A log with an editable amount.',()=>{});
    assert.equal(result.error,'');assert.equal(result.attempts,2);assert(result.vbc2.startsWith('["VBC2"'));assertUniform();
    const repair=requests[1].messages;
    assert.equal(repair[1].content,'function broken(');assert(repair[2].content.includes('A log with an editable amount.'));assert(repair[2].content.includes(compilerError('function broken(')));
    assert(/complete program|complete replacement|complete.*program/i.test(repair[2].content));
    return {attempts:result.attempts,failedSourceReplayed:true};
  });
  await runAsync('Truncated widget generation repairs a complete replacement',async()=>{
    requests.length=0;responses.push({content:'function incomplete(',finish:'length'},example);
    const result=await chat.buildMiniApp(skill+widget,'An editable amount log.',()=>{});
    assert.equal(result.error,'');assert.equal(result.attempts,2);assertUniform();
    const repair=requests[1].messages.at(-1).content;
    assert(/cut off|truncat/i.test(repair));assert(repair.includes('An editable amount log.'));
    return {attempts:2,truncationFeedback:true};
  });
  await runAsync('UI needs parser accepts one requirement without padding',async()=>{
    responses.push('["editable numeric amount"]');
    const needs=await deep.deepseek.extractUiNeeds('An editable amount.');
    assert.deepEqual(needs,['editable numeric amount']);
    const sent=requests.at(-1);assert.equal(sent.messages.at(-1).content,'An editable amount.');assert.equal(sent.temperature,0);assert.equal(sent.thinking.type,'disabled');assert.equal(sent.max_tokens,300);
    return {phrases:needs.length,temperature:sent.temperature};
  });
  await runAsync('Chat marker streaming and description handoff',async()=>{
    const description='Use a calm soft theme with a violet accent. Split a bill of 187.40 with a 12% tip among four people; show currency and editable inputs. Show the verified image https://example.com/verified.jpg.';
    const reply='Here is an editable split.\n<<app: '+description+'>>\nEach person pays 52.47.';
    responses.push(reply);let streamed='';await chat.chatReply([{role:'user',text:'Split 187.40 plus 12% tip among four people.'}],text=>{streamed=text},()=>{},new (load(path.join(base,'VeraChatStats.ets')).ReplyStats)());
    assert.equal(streamed,reply);
    const parsed=chat.parseReply(reply);assert.equal(parsed.appDescription,description);assert(parsed.appDescription.includes('calm soft theme with a violet accent'));assert(parsed.appDescription.includes('https://example.com/verified.jpg'));
    assert.equal(parsed.before,'Here is an editable split.');assert.equal(parsed.after,'Each person pays 52.47.');
    const partial=chat.parseReply('Here is the split.\n<<app: '+description);assert.equal(partial.describing,true);assert.equal(partial.appDescription,'');
    const sent=requests.at(-1).messages[0].content;
    assert(sent.includes('<<app:'));assert(/visual preferences|visual direction|style preferences/i.test(sent));assert.equal(requests.at(-1).thinking.type,'disabled');assert.equal(requests.at(-1).max_tokens,1024);return {completeMarker:true,partialMarkerHeld:true};
  });
  const revision=cp.execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim();
  const scope=['entry/src/main/resources/rawfile/vera-skill.txt','entry/src/main/resources/rawfile/vera-widget.txt','entry/src/main/ets/vera/VeraChat.ets','entry/src/main/ets/vera/DeepSeekEngine.ets','entry/src/main/ets/pages/GeneratePage.ets','docs/prompt-evaluation.md'];
  const hashes=Object.fromEntries(scope.map(p=>[p,crypto.createHash('sha256').update(read(p)).digest('hex')]));
  const diff=cp.execFileSync('git',['diff','HEAD','--',...scope],{cwd:root,encoding:'utf8'});
  const report={revision,harness_sha256:crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex'),source_sha256:hashes,uncommitted_diff_sha256:crypto.createHash('sha256').update(diff).digest('hex'),command:'node '+__filename+' '+root+' '+output,inputs:'Checked-in prompt assets and deterministic mocked HTTP replies. Actual application compiler, VM, UI decoder and prompt transport execute on host.',expected:'All prompt and generation workflow checks PASS; DeepSeek application generation uses enabled reasoning and 32768 output tokens on every attempt.',observed:checks.some(c=>c.status==='FAIL')?'FAIL':'PASS',checks,limits:['HTTP and native imports are mocked. No real model or HarmonyOS device run. Generate screen methods execute from actual source with UI bookkeeping mocked. TypeScript transpilation is not an ArkTS SDK build.']};
  fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));process.exitCode=report.observed==='PASS'?0:1;
})().catch(e=>{console.error(e);process.exitCode=1});
