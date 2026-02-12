import * as vscode from 'vscode';
import { HealthcareSkillLoader } from './skills/skill-loader';
import { HealthcareChatHandler } from './chat/chat-handler';

let skillLoader: HealthcareSkillLoader;
let chatHandler: HealthcareChatHandler;

export function activate(context: vscode.ExtensionContext) {
  console.log('Azure Healthcare Copilot extension activated');

  // Initialize skill loader
  skillLoader = new HealthcareSkillLoader(context);

  // Initialize chat handler
  chatHandler = new HealthcareChatHandler(skillLoader);

  // Register chat participant
  const participant = vscode.chat.createChatParticipant(
    'azure-healthcare',
    async (request, context, response, token) => {
      return chatHandler.handleRequest(request, context, response, token);
    }
  );

  // Set participant properties
  participant.iconPath = vscode.Uri.joinPath(context.extensionUri, 'media', 'icon.png');

  // Register commands
  context.subscriptions.push(
    vscode.commands.registerCommand('azure-healthcare.validateResource', async () => {
      await validateCurrentResource();
    }),

    vscode.commands.registerCommand('azure-healthcare.searchPatient', async () => {
      await searchPatient();
    }),

    vscode.commands.registerCommand('azure-healthcare.checkCoverage', async () => {
      await checkCoverage();
    })
  );

  context.subscriptions.push(participant);
}

async function validateCurrentResource(): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor) {
    vscode.window.showWarningMessage('No active editor');
    return;
  }

  const document = editor.document;
  if (document.languageId !== 'json') {
    vscode.window.showWarningMessage('Please open a JSON file containing a FHIR resource');
    return;
  }

  try {
    const content = document.getText();
    const resource = JSON.parse(content);

    if (!resource.resourceType) {
      vscode.window.showWarningMessage('Not a valid FHIR resource (missing resourceType)');
      return;
    }

    // In production, would call MCP server for validation
    vscode.window.showInformationMessage(
      `Validating ${resource.resourceType} resource...`
    );

    // Simulated validation result
    const diagnostics: vscode.Diagnostic[] = [];

    // Check for common issues
    if (resource.resourceType === 'Patient' && !resource.identifier) {
      diagnostics.push(
        new vscode.Diagnostic(
          new vscode.Range(0, 0, 0, 1),
          'Patient should have at least one identifier',
          vscode.DiagnosticSeverity.Warning
        )
      );
    }

    const diagnosticCollection = vscode.languages.createDiagnosticCollection('fhir');
    diagnosticCollection.set(document.uri, diagnostics);

    if (diagnostics.length === 0) {
      vscode.window.showInformationMessage('FHIR resource validation passed');
    } else {
      vscode.window.showWarningMessage(`Found ${diagnostics.length} validation issues`);
    }

  } catch (error) {
    vscode.window.showErrorMessage(`Invalid JSON: ${error}`);
  }
}

async function searchPatient(): Promise<void> {
  const name = await vscode.window.showInputBox({
    prompt: 'Enter patient name to search',
    placeHolder: 'Smith, John'
  });

  if (!name) {
    return;
  }

  vscode.window.showInformationMessage(`Searching for patient: ${name}...`);

  // In production, would call MCP server
  // For now, show placeholder
  vscode.window.showInformationMessage(
    'Patient search requires MCP server connection. Configure in settings.'
  );
}

async function checkCoverage(): Promise<void> {
  const cptCode = await vscode.window.showInputBox({
    prompt: 'Enter CPT code to check coverage',
    placeHolder: '99213'
  });

  if (!cptCode) {
    return;
  }

  vscode.window.showInformationMessage(`Checking coverage for CPT ${cptCode}...`);

  // In production, would call MCP server
  vscode.window.showInformationMessage(
    'Coverage check requires MCP server connection. Configure in settings.'
  );
}

export function deactivate() {
  console.log('Azure Healthcare Copilot extension deactivated');
}
