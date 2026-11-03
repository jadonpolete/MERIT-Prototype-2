const test=require('node:test'),assert=require('node:assert/strict'),ethers=require('ethers');
const {ChainDemo}=require('../chain.cjs'),{verifyDecision}=require('../verify.cjs'),{createServer}=require('../server.cjs');
let d;
test.before(async()=>{d=await new ChainDemo({outputDir:null}).initialize();});test.after(async()=>{await d.close();});
test('full actual-chain demo: successful DENY, block, reverted receipt and recovery',async()=>{
 const r=await d.demo();assert.equal(r.checks.length,7);assert(r.checks.every(c=>c.passed));assert.equal(r.state.events.length,13);
 for(const e of r.state.events){assert.match(e.tx_hash,/^0x[0-9a-f]{64}$/);assert(BigInt(e.gas_used)>0n);assert.equal(e.rtk_before,e.rtk_after);if(e.outcome!=='ALLOW')assert.equal(e.data_released,false);const receipt=await d.provider.getTransactionReceipt(e.tx_hash);assert.equal(receipt.status,e.receipt_status);assert.equal(receipt.gasUsed.toString(),e.gas_used);}
});
test('original role and balance reads match expected on-chain setup',async()=>{
 const s=await d.state();assert.equal(s.actors.find(a=>a.actor==='device-a').role,'SECONDARY_GROUP_HEAD');assert.equal(s.actors.find(a=>a.actor==='device-b').role,'REGULAR_MEMBER');assert.equal(s.actors.find(a=>a.actor==='visitor').role,'PRIMARY_GROUP_HEAD');assert.equal(s.actors.find(a=>a.actor==='device-b').rtk_balance,'100000.0');
});
test('receipt verification rejects missing/wrong/duplicate evidence and reverted transactions',async()=>{
 const e=d.events.find(e=>e.outcome==='ALLOW');const receipt=await d.provider.getTransactionReceipt(e.tx_hash);const expected={id:e.request_id,requester:e.requester_address,target:e.target_address};
 assert.equal(verifyDecision(receipt,d.gateway,expected).allowed,true);
 assert.equal(verifyDecision({...receipt,status:0},d.gateway,expected).verified,false);
 assert.equal(verifyDecision({...receipt,to:ethers.ZeroAddress},d.gateway,expected).verified,false);
 assert.equal(verifyDecision({...receipt,logs:[]},d.gateway,expected).verified,false);
 assert.equal(verifyDecision(receipt,d.gateway,{...expected,id:ethers.ZeroHash}).verified,false);
 assert.equal(verifyDecision(receipt,d.gateway,{...expected,requester:ethers.ZeroAddress}).verified,false);
 assert.equal(verifyDecision(receipt,d.gateway,{...expected,target:ethers.ZeroAddress}).verified,false);
 assert.equal(verifyDecision({...receipt,logs:receipt.logs.map(l=>({...l,address:ethers.ZeroAddress}))},d.gateway,expected).verified,false);
 assert.equal(verifyDecision({...receipt,logs:[...receipt.logs,...receipt.logs]},d.gateway,expected).verified,false);
});
test('direct signer identity is recorded, a denied transaction still succeeds, and disabled gateway reverts',async()=>{
 await d.reset();const denied=await d.read('visitor');assert.equal(denied.event.requester_address,d.actors.visitor.address);assert.equal(denied.event.receipt_status,1);assert.equal(denied.event.outcome,'DENY');assert.equal(denied.data,null);
 await d.setEnabled(false);const r=await d.read('device-a');assert.equal(r.event.receipt_status,0);assert.equal(r.event.decision_verified,false);assert.equal(r.data,null);await d.setEnabled(true);
});
test('HTTP input, cross-origin handling, actual read and CSV export',async()=>{
 const server=createServer(d);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const base='http://127.0.0.1:'+server.address().port;
 const post=(p,body,headers={})=>fetch(base+p,{method:'POST',headers:{'Content-Type':'application/json',...headers},body:JSON.stringify(body)});
 try{assert.equal((await post('/api/read',{actor:'nope'})).status,400);assert.equal((await post('/api/read',[])).status,400);assert.equal((await post('/api/read',{actor:'device-a'},{Origin:'http://example.invalid'})).status,403);assert.equal((await fetch(base+'/contracts/original/RoleToken.sol')).status,404);
 const r=await(await post('/api/read',{actor:'device-a'})).json();assert.equal(r.event.outcome,'ALLOW');assert.equal(r.data.sample_type,'simulated');const csv=await(await fetch(base+'/api/export.csv')).text();assert(csv.includes(r.event.tx_hash));assert(csv.includes('gas_used'));
 }finally{await new Promise(resolve=>server.close(resolve));}
});
test('reused source files match recorded original hashes and compiled artifacts are current',()=>{
 const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');const base=path.join(__dirname,'..');const provenance=require('../PROVENANCE.json'),manifest=require('../artifacts/manifest.json');
 for(const source of provenance.original_contracts){assert.equal(source.modified,false);assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(base,source.path))).digest('hex'),source.sha256);}
 for(const [file,hash]of Object.entries(manifest.sha256))assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(base,file))).digest('hex'),hash);
});
