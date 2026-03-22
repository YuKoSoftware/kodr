const { LanguageClient, TransportKind } = require("vscode-languageclient/node");
const vscode = require("vscode");

let client;

function activate(context) {
  const config = vscode.workspace.getConfiguration("kodr");
  if (!config.get("lsp.enabled", true)) return;

  const command = config.get("lsp.path", "kodr");

  const serverOptions = {
    command: command,
    args: ["lsp"],
    transport: TransportKind.stdio,
  };

  const clientOptions = {
    documentSelector: [{ scheme: "file", language: "kodr" }],
  };

  client = new LanguageClient("kodr", "Kodr Language Server", serverOptions, clientOptions);
  client.start();
}

function deactivate() {
  if (client) return client.stop();
}

module.exports = { activate, deactivate };
