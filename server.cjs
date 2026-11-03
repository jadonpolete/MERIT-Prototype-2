const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),{execFile}=require('node:child_process');
const {ChainDemo}=require('./chain.cjs');
const fields=['run_id','request_id','timestamp_utc','scenario','requester','target','outcome','reason','decision_verified','receipt_status','tx_hash','block_number','gas_used','fee_wei','rtk_before','rtk_after','window_count','blocked_until_before','blocked_until_after','confirmation_ms','data_released'];
function csv(events){const q=x=>'"'+String(x??'').replaceAll('"','""')+'"';return [fields.join(','),...events.map(e=>fields.map(k=>q(e[k])).join(','))].join('\r\n')+'\r\n';}
function createServer(demo){return http.createServer(async(req,res)=>{
 const send=(status,data,type='application/json',filename)=>{const bytes=Buffer.isBuffer(data)?data:Buffer.from(type==='application/json'?JSON.stringify(data):data);res.writeHead(status,{'Content-Type':type+'; charset=utf-8','Content-Length':bytes.length,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...(filename?{'Content-Disposition':`attachment; filename="${filename}"`}:{})});res.end(bytes);};
 const route=new URL(req.url,'http://127.0.0.1').pathname;
 try{
  if(req.method==='GET'){
   if(route==='/api/progress')return send(200,demo.progress);
   if(route==='/api/state')return send(200,await demo.exclusive(()=>demo.state()));
   if(route==='/api/export.json')return send(200,await demo.exclusive(()=>demo.state()),'application/json',demo.runId+'.json');
   if(route==='/api/export.csv')return send(200,await demo.exclusive(()=>csv(demo.events)),'text/csv',demo.runId+'.csv');
   const assets={'/':['index.html','text/html'],'/app.js':['app.js','text/javascript'],'/style.css':['style.css','text/css']};
   if(Object.hasOwn(assets,route)){const [name,type]=assets[route];return send(200,fs.readFileSync(path.join(__dirname,'web',name)),type);}
   return send(404,{error:'NOT_FOUND'});
  }
  if(req.method!=='POST')return send(405,{error:'METHOD_NOT_ALLOWED'});
  if(req.headers.origin&&req.headers.origin!=='http://'+req.headers.host)return send(403,{error:'ORIGIN_NOT_ALLOWED'});
  if(!req.headers['content-type']?.startsWith('application/json'))return send(400,{error:'JSON_REQUIRED'});
  let body='',size=0;for await(const chunk of req){size+=chunk.length;if(size>4096)return send(413,{error:'BODY_TOO_LARGE'});body+=chunk;}
  let p;try{p=JSON.parse(body);}catch{return send(400,{error:'INVALID_JSON'});}
  if(!p||typeof p!=='object'||Array.isArray(p))return send(400,{error:'INVALID_BODY'});
  const exact=keys=>Object.keys(p).sort().join(',')===keys.sort().join(',');
  if(route==='/api/read'&&exact(['actor'])&&['device-a','device-b','visitor'].includes(p.actor))return send(200,await demo.exclusive(()=>demo.read(p.actor)));
  if(route==='/api/reset'&&exact([]))return send(200,await demo.exclusive(()=>demo.reset()));
  if(route==='/api/demo'&&exact([]))return send(200,await demo.exclusive(()=>demo.demo()));
  if(route==='/api/enabled'&&exact(['enabled'])&&typeof p.enabled==='boolean')return send(200,await demo.exclusive(()=>demo.setEnabled(p.enabled)));
  if(route==='/api/advance'&&exact([]))return send(200,await demo.exclusive(()=>demo.advance(11)));
  return send(400,{error:'UNKNOWN_ROUTE_OR_INVALID_BODY'});
 }catch(e){send(500,{error:e.shortMessage||e.message,data:null});}
});}
async function main(){
 const index=process.argv.indexOf('--port');const port=index<0?8766:Number(process.argv[index+1]);if(!Number.isInteger(port)||port<1||port>65535)throw Error('Use a port from 1 to 65535');
 const d=new ChainDemo();console.log('Starting embedded local chain and deploying selected MERIT contracts…');await d.initialize();
 const server=createServer(d);server.on('error',async e=>{console.error(e.message);await d.close();process.exitCode=1;});
 server.listen(port,'127.0.0.1',()=>{const url='http://127.0.0.1:'+port;console.log('MERIT Prototype 2: '+url+'\nKeep this terminal open. Ctrl+C stops the server.\nLocal development chain only; sensor data is simulated.');if(!process.argv.includes('--no-browser')){const command=process.platform==='win32'?'cmd':process.platform==='darwin'?'open':'xdg-open';const args=process.platform==='win32'?['/c','start','',url]:[url];execFile(command,args,()=>{});}});
 process.on('SIGINT',()=>server.close(async()=>{await d.close();process.exit(0)}));
}
if(require.main===module)main().catch(e=>{console.error('Startup failed:',e.message);process.exit(1)});
module.exports={createServer,csv};
