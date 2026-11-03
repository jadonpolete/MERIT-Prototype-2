const fs = require('node:fs'), path = require('node:path'), solc = require('solc');
const names = ['contracts/original/RoleToken.sol', 'contracts/original/RoleBasedAccessControl.sol', 'contracts/ReceiptDecisionGateway.sol'];
const sources = Object.fromEntries(names.map(n => [n, {content: fs.readFileSync(path.join(__dirname, n),'utf8')}]));
const input = {language:'Solidity',sources,settings:{optimizer:{enabled:true,runs:200},evmVersion:'shanghai',outputSelection:{'*':{'*':['abi','evm.bytecode.object']}}}};
const result = JSON.parse(solc.compile(JSON.stringify(input),{import:n=>{try{return {contents:fs.readFileSync(path.join(__dirname,'node_modules',n),'utf8')}}catch{return {error:'Missing import: '+n}}}}));
const errors=(result.errors||[]).filter(x=>x.severity==='error');if(errors.length)throw Error(errors.map(x=>x.formattedMessage).join('\n'));
fs.mkdirSync(path.join(__dirname,'artifacts'),{recursive:true});
for(const [file, contracts] of Object.entries(result.contracts)) for(const [name,c] of Object.entries(contracts)) if(names.includes(file)) {
 fs.writeFileSync(path.join(__dirname,'artifacts',name+'.json'),JSON.stringify({contractName:name,source:file,compiler:solc.version(),abi:c.abi,bytecode:'0x'+c.evm.bytecode.object},null,2));
}
console.log('Compiled original RoleToken, original RoleBasedAccessControl, and new ReceiptDecisionGateway.');
const crypto=require('node:crypto');
const files=[...names,...['RoleToken','RoleBasedAccessControl','ReceiptDecisionGateway'].map(n=>'artifacts/'+n+'.json')];
const manifest={compiler:solc.version(),evmVersion:'shanghai',optimizerRuns:200,sha256:Object.fromEntries(files.map(n=>[n,crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname,n))).digest('hex')]))};
fs.writeFileSync(path.join(__dirname,'artifacts/manifest.json'),JSON.stringify(manifest,null,2));
