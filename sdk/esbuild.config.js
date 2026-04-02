const esbuild = require('esbuild');

const shared = { entryPoints: ['src/index.ts'], bundle: true, sourcemap: true };

Promise.all([
  esbuild.build({ ...shared, format: 'esm',  outfile: 'dist/index.mjs' }),
  esbuild.build({ ...shared, format: 'cjs',  outfile: 'dist/index.cjs' }),
  esbuild.build({ ...shared, format: 'iife', outfile: 'dist/rum-sdk.min.js',
    globalName: 'RumSDK', minify: true }),
]).catch(() => process.exit(1));
