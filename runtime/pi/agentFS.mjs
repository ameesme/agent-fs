// Trusted runtime extension: conversation context, task updates and file-only tools.
import * as fs from 'node:fs';
import * as path from 'node:path';
import { Text } from '@earendil-works/pi-tui';

// Resolve existing ancestors as well as the leaf, so symlinks cannot escape a root.
function resolveFilePath(filePath) {
  const absolutePath = path.resolve(filePath);

  try {
    return fs.realpathSync(absolutePath);
  } catch (error) {
    if (error.code !== 'ENOENT') {
      throw error;
    }
  }

  // A write target may not exist yet, or may be a dangling symlink.
  const entry = fs.lstatSync(absolutePath, { throwIfNoEntry: false });
  const parentPath = path.dirname(absolutePath);

  if (entry?.isSymbolicLink()) {
    const linkTarget = fs.readlinkSync(absolutePath);
    return resolveFilePath(path.resolve(parentPath, linkTarget));
  }

  if (parentPath === absolutePath) {
    return absolutePath;
  }

  return path.join(resolveFilePath(parentPath), path.basename(absolutePath));
}

function deliverTaskUpdates(pi, inboxPath, ui) {
  if (!fs.existsSync(inboxPath)) {
    return;
  }

  const pendingFiles = fs.readdirSync(inboxPath)
    .filter(name => name.endsWith('.txt'))
    .sort();

  for (const filename of pendingFiles) {
    const updatePath = path.join(inboxPath, filename);

    try {
      const message = fs.readFileSync(updatePath, 'utf8');
      pi.sendUserMessage(message, { deliverAs: 'followUp' });
      fs.unlinkSync(updatePath);
    } catch (error) {
      ui.notify(`Task update remains pending: ${error.message}`, 'warning');
      break;
    }
  }
}

function describeAgents(agentsDirectory) {
  const agents = [];

  for (const name of fs.readdirSync(agentsDirectory).sort()) {
    if (name === process.env.AGENT_NAME) {
      continue;
    }

    const configPath = path.join(agentsDirectory, name, 'agent.json');
    const dockerfilePath = path.join(agentsDirectory, name, 'Dockerfile');
    if (!fs.existsSync(configPath) || !fs.existsSync(dockerfilePath)) {
      continue;
    }

    try {
      const agent = JSON.parse(fs.readFileSync(configPath, 'utf8'));
      agents.push(`- ${name}: ${agent.description || 'No description provided.'}`);
    } catch (error) {
      console.warn(`Could not read agent ${name}: ${error.message}`);
    }
  }

  return agents.length > 0 ? agents.join('\n') : 'No agents available.';
}

export default function agentFs(pi) {
  const configPath = process.env.AGENT_FS_CONFIG || '/agent/agent.json';
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const inboxRoot = process.env.AGENT_FS_INBOX || '/data/.inbox';
  let updateTimer;

  pi.on('before_agent_start', (event, context) => {
    const sessionId = context.sessionManager.getSessionId();
    const conversationId = process.env.AGENT_FS_CONVERSATION || `native-${sessionId}`;
    const instructions = [
      event.systemPrompt,
      '',
      `Conversation id: ${conversationId}`,
      'Use this exact id for GROUP when dispatching tasks.',
    ];

    if (process.env.AGENT_NAME === 'main') {
      instructions.push('', 'Available agents:', describeAgents('/data/agents'));
    }

    return {
      systemPrompt: instructions.join('\n'),
    };
  });

  if (config.allowPaths) {
    pi.on('tool_call', (event, context) => {
      const isFileTool = ['read', 'write'].includes(event.toolName);
      const hasFilePath = typeof event.input.path === 'string';

      if (!isFileTool || !hasFilePath) {
        return {
          block: true,
          reason: 'This agent may only read and write its task folders.',
        };
      }

      const requestedPath = path.resolve(context.cwd, event.input.path);
      const resolvedPath = resolveFilePath(requestedPath);
      const isAllowed = config.allowPaths.some(folder => {
        const allowedFolder = resolveFilePath(folder);
        return resolvedPath === allowedFolder || resolvedPath.startsWith(allowedFolder + path.sep);
      });

      if (!isAllowed) {
        return {
          block: true,
          reason: 'Path is outside this agent’s task folders.',
        };
      }
    });
  }

  pi.on('session_start', (_event, context) => {
    clearInterval(updateTimer);

    if (process.env.AGENT_FS_NATIVE !== '1') {
      return;
    }

    if (process.env.AGENT_NAME === 'main' && context.hasUI) {
      context.ui.setHeader((_tui, theme) => new Text(
        `${theme.fg('accent', 'agentFS')}\n\nAvailable agents:\n${describeAgents('/data/agents')}`,
        1, 1,
      ));
    }

    const sessionId = context.sessionManager.getSessionId();
    const inboxPath = path.join(inboxRoot, `native-${sessionId}`);

    updateTimer = setInterval(() => {
      deliverTaskUpdates(pi, inboxPath, context.ui);
    }, 1000);

    updateTimer.unref();
  });

  pi.on('session_shutdown', () => {
    clearInterval(updateTimer);
  });
}
