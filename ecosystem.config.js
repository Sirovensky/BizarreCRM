const path = require('path');
const root = __dirname;

module.exports = {
  apps: [
    {
      name: 'bizarre-crm',
      script: 'src/index.ts',
      interpreter: 'node',
      interpreter_args: '--import tsx/esm',
      cwd: path.join(root, 'packages/server'),
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '512M',
      restart_delay: 2000,
      max_restarts: 10,
      min_uptime: '10s',
      env: {
        NODE_ENV: 'development',
        PORT: 443,
      },
    },
  ],
};
