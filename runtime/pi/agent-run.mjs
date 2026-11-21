#!/usr/bin/env node
// One launch path for interactive main, channel sessions and queued workers.
import { existsSync, readFileSync } from 'node:fs';
import { spawn } from 'node:child_process';

const configPath = process.env.SHOEBOX_CONFIG || '/agent/agent.json';
const config = JSON.parse(readFileSync(configPath, 'utf8'));
const model = config.model || process.env.PI_MODEL;
// Pi reads prompt arguments that are file paths; agent.json's legacy instruction still comes first.
const prompts = [config.instruction, existsSync('/agent/soul.md') && '/agent/soul.md'].filter(Boolean);

// Load only the resources declared by shoebox, rather than discovering them.
const piArguments = [
  '--no-extensions',
  '--no-context-files',
  '--no-prompt-templates',
  '--no-skills',
  '--extension', '/usr/local/lib/shoebox/shoebox.mjs',
  '--system-prompt', prompts[0] ?? '',
  '--tools', [...config.tools, ...(config.mcpServers ? ['codemode'] : [])].join(','),
];

// MCP servers from agent.json reach the model through codemode scripts.
if (config.mcpServers) {
  piArguments.push('--extension', 'builtin:mcp', '--extension', 'builtin:codemode');
}

if (prompts[1]) {
  piArguments.push('--append-system-prompt', prompts[1]);
}

if (model) {
  piArguments.push('--model', model);
}

for (const skill of config.skills || []) {
  piArguments.push('--skill', `/agent/skills/${skill}`);
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
