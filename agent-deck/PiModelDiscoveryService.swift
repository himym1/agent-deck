import Foundation

struct PiModelDiscoveryService: Sendable {
    private static let defaultSupportedThinkingLevels = ["off", "minimal", "low", "medium", "high"]

    private let commandRunner: CommandRunning
    private let piResolver: PiExecutableResolver

    init(commandRunner: CommandRunning = CommandRunner(), piResolver: PiExecutableResolver = PiExecutableResolver()) {
        self.commandRunner = commandRunner
        self.piResolver = piResolver
    }

    func loadAvailableModels() async -> [AvailableModel] {
        let piCommand = piResolver.resolve()?.path ?? "pi"

        do {
            let result = try await commandRunner.run(
                piCommand,
                arguments: ["--list-models"],
                currentDirectoryURL: nil,
                timeout: 12,
                environment: nil
            )
            guard result.exitCode == 0 else { return [] }
            let output = result.stdout.isEmpty ? result.stderr : result.stdout
            let exactThinkingLevels = await loadModelThinkingLevels(fromPiListOutput: output, piPath: piCommand)
            return Self.parseAvailableModels(from: output, exactThinkingLevels: exactThinkingLevels)
        } catch {
            return []
        }
    }

    private func loadModelThinkingLevels(fromPiListOutput text: String, piPath: String) async -> [String: [String]] {
        let knownModels: [[String: Any]] = Self.availableModelDescriptors(fromPiListOutput: text).map {
            ["provider": $0.provider, "model": $0.model, "supportsThinking": $0.supportsThinking]
        }
        guard !knownModels.isEmpty,
              let inputData = try? JSONSerialization.data(withJSONObject: knownModels),
              let inputText = String(data: inputData, encoding: .utf8)
        else {
            return [:]
        }

        // Walk up from the real pi binary location to find models.js, covering nvm,
        // volta, fnm, local installs, and anything else where the binary is a symlink
        // into a node_modules tree. Falls back to known Homebrew paths.
        let script = #"""
import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, resolve } from 'node:path';

const candidates = [];

function expandHome(path) {
  return path.replace(/^\$HOME\b|^~(?=\/)/, homedir()).replace(/^\$\{HOME\}/, homedir());
}

function addModelCandidatesFromCliPath(cliPath) {
  try {
    let dir = dirname(realpathSync(expandHome(cliPath)));
    for (let i = 0; i < 10; i++) {
      const earendil = resolve(dir, 'node_modules/@earendil-works/pi-ai/dist/models.js');
      const mario    = resolve(dir, 'node_modules/@mariozechner/pi-ai/dist/models.js');
      candidates.push(earendil, mario);
      const parent = dirname(dir);
      if (parent === dir) break;
      dir = parent;
    }
  } catch {}
}

const piPath = process.env.AGENT_DECK_PI_PATH;
if (piPath && existsSync(piPath)) {
  addModelCandidatesFromCliPath(piPath);
  try {
    const wrapper = readFileSync(piPath, 'utf8');
    const cliMatch = wrapper.match(/PI_CLI=["']?([^"'\n]+)/);
    if (cliMatch?.[1]) addModelCandidatesFromCliPath(cliMatch[1]);
  } catch {}
}

candidates.push(
  resolve(homedir(), '.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/models.js'),
  resolve(homedir(), '.npm-global/lib/node_modules/@mariozechner/pi-coding-agent/node_modules/@mariozechner/pi-ai/dist/models.js'),
  '/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/models.js',
  '/opt/homebrew/lib/node_modules/@mariozechner/pi-coding-agent/node_modules/@mariozechner/pi-ai/dist/models.js',
  '/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/models.js',
  '/usr/local/lib/node_modules/@mariozechner/pi-coding-agent/node_modules/@mariozechner/pi-ai/dist/models.js',
);

const modulePath = candidates.find((path) => existsSync(path));
if (!modulePath) throw new Error('Could not locate pi-ai models.js');

const models = await import(modulePath);
const input = JSON.parse(process.env.AGENT_DECK_MODEL_INPUT ?? '[]');
const defaultThinkingLevels = ['off', 'minimal', 'low', 'medium', 'high'];

function loadCustomModelConfig() {
  const configPath = resolve(homedir(), '.pi/agent/models.json');
  if (!existsSync(configPath)) return {};
  try {
    return JSON.parse(readFileSync(configPath, 'utf8'));
  } catch {
    return {};
  }
}

const customModelConfig = loadCustomModelConfig();
const customProviders = customModelConfig.providers ?? customModelConfig;

function customModelFor(provider, modelId) {
  const providerConfig = customProviders?.[provider];
  const providerModels = Array.isArray(providerConfig?.models) ? providerConfig.models : [];
  return providerModels.find((model) => model?.id === modelId);
}

function supportedThinkingLevelsFor(model, supportsThinking) {
  if (!supportsThinking || model?.reasoning === false) return ['off'];
  if (model?.reasoning === true && typeof models.getSupportedThinkingLevels === 'function') {
    try {
      return models.getSupportedThinkingLevels(model);
    } catch {}
  }
  return defaultThinkingLevels;
}

const result = {};
for (const item of input) {
  const identifier = `${item.provider}/${item.model}`;
  const supportsThinking = item.supportsThinking === true;
  let model = customModelFor(item.provider, item.model);
  if (!model) {
    try {
      model = models.getModel(item.provider, item.model);
    } catch {}
  }
  result[identifier] = supportedThinkingLevelsFor(model, supportsThinking);
}
process.stdout.write(JSON.stringify(result));
"""#

        do {
            let result = try await commandRunner.run(
                "node",
                arguments: ["--input-type=module", "--eval", script],
                currentDirectoryURL: nil,
                timeout: 8,
                environment: ["AGENT_DECK_MODEL_INPUT": inputText, "AGENT_DECK_PI_PATH": piPath]
            )
            guard result.exitCode == 0,
                  let data = result.stdout.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: [String]]
            else {
                return [:]
            }
            return object
        } catch {
            return [:]
        }
    }

    static func availableModelIdentifiers(fromPiListOutput text: String) -> [(provider: String, model: String)] {
        availableModelDescriptors(fromPiListOutput: text).map { (provider: $0.provider, model: $0.model) }
    }

    private static func availableModelDescriptors(fromPiListOutput text: String) -> [(provider: String, model: String, supportsThinking: Bool)] {
        text.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 5 else { return nil }
            return (provider: parts[0], model: parts[1], supportsThinking: parts[4].lowercased() == "yes")
        }
    }

    static func parseAvailableModels(from text: String, exactThinkingLevels: [String: [String]]) -> [AvailableModel] {
        text
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line in
                let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard parts.count >= 6 else { return nil }
                let identifier = "\(parts[0])/\(parts[1])"
                let supportsThinking = parts[4].lowercased() == "yes"
                return AvailableModel(
                    provider: parts[0],
                    model: parts[1],
                    contextWindow: parts[2],
                    maxOutput: parts[3],
                    supportsThinking: supportsThinking,
                    supportsImages: parts[5].lowercased() == "yes",
                    supportedThinkingLevels: exactThinkingLevels[identifier] ?? (supportsThinking ? Self.defaultSupportedThinkingLevels : ["off"])
                )
            }
    }
}
