function verifyDecision(receipt, gateway, expected) {
  if (!receipt || receipt.status !== 1) return {verified:false,reason:'TRANSACTION_REVERTED_OR_UNCONFIRMED'};
  if (!receipt.to || receipt.to.toLowerCase() !== gateway.target.toLowerCase()) return {verified:false,reason:'WRONG_RECEIPT_TARGET'};
  const matches=[];
  for (const log of receipt.logs) {
    if (log.address.toLowerCase() !== gateway.target.toLowerCase()) continue;
    try {const p=gateway.interface.parseLog(log);
      if(p?.name==='Decision' && p.args.requestId===expected.id &&
        p.args.requester.toLowerCase()===expected.requester.toLowerCase() &&
        p.args.target.toLowerCase()===expected.target.toLowerCase()) matches.push(p.args);
    } catch {}
  }
  if(matches.length!==1)return {verified:false,reason:'MISSING_OR_AMBIGUOUS_MATCHING_DECISION'};
  const d=matches[0];
  return {verified:true,allowed:d.allowed,reason:d.reason,count:Number(d.count),blockedUntil:Number(d.blockedUntil)};
}
module.exports={verifyDecision};
