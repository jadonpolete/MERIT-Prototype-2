const ganache=require('ganache'), ethers=require('ethers'), fs=require('node:fs'), path=require('node:path'), crypto=require('node:crypto');
const {verifyDecision}=require('./verify.cjs');
const artifact=n=>require('./artifacts/'+n+'.json');
const roles=['NONE','ADMIN','PRIMARY_GROUP_HEAD','SECONDARY_GROUP_HEAD','REGULAR_MEMBER'];
class ChainDemo {
 constructor({outputDir=path.join(__dirname,'output')}={}){this.outputDir=outputDir;this.events=[];this.chain=null;this.tail=Promise.resolve();this.progress={phase:'STARTING',message:'Deploying local contracts'};}
 exclusive(fn){const result=this.tail.then(fn);this.tail=result.catch(()=>{});return result;}
 async initialize(){
  const manifest=require('./artifacts/manifest.json');
  for(const [file,hash] of Object.entries(manifest.sha256)) {
   const actual=crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname,file))).digest('hex');
   if(actual!==hash)throw Error('Source/artifact mismatch: '+file+'. Run npm run compile after edits.');
  }
  this.chain=ganache.provider({logging:{quiet:true},wallet:{totalAccounts:6},chain:{chainId:1337,hardfork:'shanghai'},miner:{instamine:'eager'}});
  this.provider=new ethers.BrowserProvider(this.chain);this.provider.pollingInterval=50;
  this.signers=await Promise.all([0,1,2,3,4].map(n=>this.provider.getSigner(n)));
  this.accounts=await Promise.all(this.signers.map(s=>s.getAddress()));
  this.runId='chain-'+crypto.randomUUID().slice(0,8);await this.deploy();return this;
 }
 async deploy(){
  this.progress={phase:'DEPLOYING',message:'Deploying original contracts and new adapter'};
  const [admin,head,b,a,visitor]=this.accounts;
  const deploy=async(name,args)=>{const f=artifact(name);const c=await new ethers.ContractFactory(f.abi,f.bytecode,this.signers[0]).deploy(...args);await c.waitForDeployment();return c;};
  this.token=await deploy('RoleToken',[admin]);this.roles=await deploy('RoleBasedAccessControl',[this.token.target,admin]);
  this.gateway=await deploy('ReceiptDecisionGateway',[this.roles.target,b]);
  for(const [addr,name,type] of [[head,'Lab primary head','lab'],[a,'Device A','lab'],[b,'Device B','lab'],[visitor,'Visitor','visitor-group'],[this.gateway.target,'Prototype adapter','adapter-group']]) {
   await (await this.token.assignRole(addr,name,type)).wait();
  }
  this.actors={'device-a':{address:a,signer:this.signers[3]},'device-b':{address:b,signer:this.signers[2]},visitor:{address:visitor,signer:this.signers[4]}};
  this.events=[];this.progress={phase:'READY',message:'Local chain ready'};
 }
 async reset(){this.runId='chain-'+crypto.randomUUID().slice(0,8);await this.deploy();return this.state();}
 async actorState(actor){
  const address=this.actors[actor].address;
  const [balance,role,window]=await Promise.all([this.token.balanceOf(address),this.token.getRole(address),this.gateway.windows(address)]);
  return {actor,address,role:roles[Number(role)],rtk_balance:ethers.formatUnits(balance,18),window_started:Number(window.started),window_count:Number(window.count),blocked_until:Number(window.blockedUntil)};
 }
 async state(){
  const block=await this.provider.send('eth_getBlockByNumber',['latest',false]);
  return {run_id:this.runId,chain_id:1337,chain_mode:'embedded_local_ganache',block_number:Number(BigInt(block.number)),block_timestamp:Number(BigInt(block.timestamp)),enabled:await this.gateway.enabled(),
   contracts:{RoleToken:this.token.target,RoleBasedAccessControl:this.roles.target,ReceiptDecisionGateway:this.gateway.target},
   actors:await Promise.all(Object.keys(this.actors).map(n=>this.actorState(n))),events:this.events.slice(-100),event_count:this.events.length,progress:this.progress,
   config:{request_limit:5,window_seconds:10,block_seconds:8}};
 }
 async read(actor,scenario='manual'){
  if(!Object.hasOwn(this.actors,actor))throw Error('Unknown actor');
  const before=await this.actorState(actor),id=ethers.hexlify(crypto.randomBytes(32));
  const started=performance.now();this.progress={phase:'SUBMITTING',message:`${actor} asks for B readings`};
  let receipt=null,hash=null,verification={verified:false,reason:'NO_CONFIRMED_RECEIPT'},error=null;
  try {
   const tx=await this.gateway.connect(this.actors[actor].signer).requestRead(id,{gasLimit:600000});hash=tx.hash;
   this.progress={phase:'SUBMITTED',message:'Waiting for a mined receipt',tx_hash:hash};
   try{receipt=await tx.wait(1,15000);}catch(e){receipt=e.receipt||null;if(!receipt)throw e;}
   verification=verifyDecision(receipt,this.gateway,{id,requester:before.address,target:this.actors['device-b'].address});
  }catch(e){error=e.shortMessage||e.message;}
  const after=await this.actorState(actor);
  const outcome=!verification.verified?'ERROR':verification.allowed?'ALLOW':verification.reason.includes('BLOCKED')||verification.reason==='EXCESSIVE_REQUESTS'?'BLOCK':'DENY';
  const block=receipt?await this.provider.getBlock(receipt.blockNumber):null;
  const event={run_id:this.runId,request_id:id,timestamp_utc:new Date().toISOString(),scenario,requester:actor,requester_address:before.address,target:'device-b',target_address:this.actors['device-b'].address,
   outcome,reason:verification.reason,decision_verified:verification.verified,receipt_status:receipt?.status??null,tx_hash:hash,block_number:receipt?.blockNumber??null,block_hash:receipt?.blockHash??null,
   chain_timestamp:block?.timestamp??null,gas_used:receipt?.gasUsed.toString()??null,gas_price_wei:receipt?.gasPrice.toString()??null,
   fee_wei:receipt?(receipt.gasUsed*receipt.gasPrice).toString():null,
   rtk_before:before.rtk_balance,rtk_after:after.rtk_balance,window_count:verification.count??null,blocked_until_before:before.blocked_until,blocked_until_after:after.blocked_until,
   confirmation_ms:Number((performance.now()-started).toFixed(2)),data_released:verification.verified&&verification.allowed===true,error};
  this.events.push(event);if(this.outputDir){fs.mkdirSync(this.outputDir,{recursive:true});fs.appendFileSync(path.join(this.outputDir,this.runId+'.jsonl'),JSON.stringify(event)+'\n');}
  this.progress={phase:'CONFIRMED',message:`${outcome}: ${verification.reason}`,tx_hash:hash};
  return {event,data:event.data_released?{device:'device-b',temperature_c:24.6,humidity_percent:52,sample_type:'simulated'}:null};
 }
 async setEnabled(value){this.progress={phase:'ADMIN_TRANSACTION',message:'Changing new adapter state'};const receipt=await(await this.gateway.setEnabled(value)).wait();this.progress={phase:'READY',message:'Adapter '+(value?'enabled':'disabled')};return {enabled:await this.gateway.enabled(),tx_hash:receipt.hash,block_number:receipt.blockNumber,gas_used:receipt.gasUsed.toString()};}
 async advance(seconds){await this.chain.request({method:'evm_increaseTime',params:[seconds]});await this.chain.request({method:'evm_mine',params:[]});return this.state();}
 async demo(){
  await this.reset();const checks=[];const check=(name,passed)=>checks.push({name,passed});
  let r=await this.read('device-a','approved');check('Confirmed original-role policy allows A → B',r.event.outcome==='ALLOW'&&r.data!==null);
  r=await this.read('visitor','unauthorized');check('Successful transaction contains DENY; no sensor data',r.event.receipt_status===1&&r.event.outcome==='DENY'&&r.data===null);
  // Clear the request window using local development-chain time, keeping real receipts.
  await this.advance(11);
  const results=[];for(let i=0;i<8;i++)results.push(await this.read('device-a','bounded_repeated_requests'));
  check('New adapter records excess-request block on chain',results[5].event.reason==='EXCESSIVE_REQUESTS'&&results[5].data===null&&results[5].event.blocked_until_after>0);
  r=await this.read('device-b','control');check('B still reads while A is blocked',r.event.outcome==='ALLOW'&&r.data!==null);
  await this.setEnabled(false);r=await this.read('device-a','reverted_transaction');
  check('Reverted transaction has status 0; no verified decision or data',r.event.receipt_status===0&&!r.event.decision_verified&&r.data===null);
  await this.setEnabled(true);await this.advance(11);r=await this.read('device-a','recovery');
  check('Development-chain time advance demonstrates recovery',r.event.outcome==='ALLOW'&&r.data!==null);
  check('Actual RTK balances unchanged: this adapter has no token penalties',this.events.every(e=>e.rtk_before===e.rtk_after));
  return {checks,state:await this.state(),note:'Actual local-chain receipts. Demo advances chain time twice (11 seconds each) to isolate the burst and show recovery. Time advancement is a development-chain shortcut.'};
 }
 async close(){if(this.chain)await this.chain.disconnect();this.provider?.destroy();}
}
module.exports={ChainDemo};
