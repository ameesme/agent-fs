#!/usr/bin/env node
// One launch path for interactive main, bridge sessions and queued workers.
import { readFileSync } from 'node:fs';
import { spawn } from 'node:child_process';

const configPath = process.env.AGENT_FS_CONFIG || '/agent/agent.json';
const config = JSON.parse(readFileSync(configPath, 'utf8'));
const model = process.env.PI_MODEL || config.model;

// Load only the resources declared by agentFS, rather than discovering them.
const piArguments = [
  '--no-extensions',
  '--no-mcp',
  '--no-context-files',
  '--no-prompt-templates',
  '--no-skills',
  '--extension', '/usr/local/lib/agent-fs/agentFS.mjs',
  '--system-prompt', config.instruction,
  '--tools', config.tools.join(','),
];

if (model) {
  piArguments.push('--model', model);
}

for (const skill of config.skills || []) {
  piArguments.push('--skill', `/agent/home/.agents/skills/${skill}`);
}

// Pass through the caller's mode, session options and prompts.
piArguments.push(...process.argv.slice(2));
const pi = spawn('pi', piArguments, { stdio: 'inherit' });

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => pi.kill(signal));
}

pi.on('error', error => {
  console.error(error.message);
  process.exitCode = 1;
});

pi.on('exit', (exitCode, signal) => {
  if (exitCode !== null) {
    process.exitCode = exitCode;
  } else if (signal === 'SIGINT') {
    process.exitCode = 130;
  } else {
    process.exitCode = 1;
  }
});
