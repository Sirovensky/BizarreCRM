const m = await import('../packages/server/src/config.ts');
console.log(JSON.stringify({
  envBefore: process.env.MULTI_TENANT,
  cfgMT: m.config.multiTenant,
  baseDomain: m.config.baseDomain,
  nodeEnv: m.config.nodeEnv,
  cwd: process.cwd(),
}, null, 2));
