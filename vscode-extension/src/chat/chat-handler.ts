import * as vscode from 'vscode';
import { HealthcareSkillLoader } from '../skills/skill-loader';

type ChatCommand = 'fhir' | 'dicom' | 'pa' | 'validate';

export class HealthcareChatHandler {
  constructor(private skillLoader: HealthcareSkillLoader) {}

  async handleRequest(
    request: vscode.ChatRequest,
    context: vscode.ChatContext,
    response: vscode.ChatResponseStream,
    token: vscode.CancellationToken
  ): Promise<vscode.ChatResult> {
    const command = request.command as ChatCommand | undefined;

    // Handle specific commands
    if (command) {
      return this.handleCommand(command, request, context, response, token);
    }

    // General healthcare query
    return this.handleGeneralQuery(request, context, response, token);
  }

  private async handleCommand(
    command: ChatCommand,
    request: vscode.ChatRequest,
    context: vscode.ChatContext,
    response: vscode.ChatResponseStream,
    token: vscode.CancellationToken
  ): Promise<vscode.ChatResult> {
    switch (command) {
      case 'fhir':
        return this.handleFhirCommand(request, response, token);
      case 'dicom':
        return this.handleDicomCommand(request, response, token);
      case 'pa':
        return this.handlePaCommand(request, response, token);
      case 'validate':
        return this.handleValidateCommand(request, response, token);
      default:
        response.markdown('Unknown command. Available commands: /fhir, /dicom, /pa, /validate');
        return { metadata: { command: 'unknown' } };
    }
  }

  private async handleFhirCommand(
    request: vscode.ChatRequest,
    response: vscode.ChatResponseStream,
    token: vscode.CancellationToken
  ): Promise<vscode.ChatResult> {
    // Load FHIR skill context
    const skill = this.skillLoader.getSkill('azure-fhir-developer');

    if (skill) {
      response.markdown(`Using **${skill.name}** skill for FHIR guidance.\n\n`);
    }

    // Get available language models
    const models = await vscode.lm.selectChatModels({ family: 'gpt-4o' });

    if (models.length === 0) {
      response.markdown('No language model available. Please ensure GitHub Copilot is activated.');
      return { metadata: { command: 'fhir', error: 'no_model' } };
    }

    const model = models[0];

    // Build messages with skill context
    const messages: vscode.LanguageModelChatMessage[] = [
      vscode.LanguageModelChatMessage.User(
        `You are an Azure FHIR development expert. ${skill?.content || ''}\n\nUser question: ${request.prompt}`
      ),
    ];

    try {
      const chatResponse = await model.sendRequest(messages, {}, token);

      for await (const fragment of chatResponse.text) {
        response.markdown(fragment);
      }
    } catch (error) {
      response.markdown(`Error: ${error}`);
    }

    return { metadata: { command: 'fhir' } };
  }

  private async handleDicomCommand(
    request: vscode.ChatRequest,
    response: vscode.ChatResponseStream,
    token: vscode.CancellationToken
  ): Promise<vscode.ChatResult> {
    const skill = this.skillLoader.getSkill('azure-health-data-services');

    if (skill) {
      response.markdown(`Using **${skill.name}** skill for DICOM guidance.\n\n`);
    }

    const models = await vscode.lm.selectChatModels({ family: 'gpt-4o' });

    if (models.length === 0) {
      response.markdown('No language model available.');
      return { metadata: { command: 'dicom', error: 'no_model' } };
    }

    const model = models[0];

    const messages: vscode.LanguageModelChatMessage[] = [
      vscode.LanguageModelChatMessage.User(
        `You are an Azure Health Data Services expert specializing in DICOM. ${skill?.content || ''}\n\nUser question: ${request.prompt}`
      ),
    ];

    try {
      const chatResponse = await model.sendRequest(messages, {}, token);

      for await (const fragment of chatResponse.text) {
        response.markdown(fragment);
      }
    } catch (error) {
      response.markdown(`Error: ${error}`);
    }

    return { metadata: { command: 'dicom' } };
  }

  private async handlePaCommand(
    request: vscode.ChatRequest,
    response: vscode.ChatResponseStream,
    token: vscode.CancellationToken
  ): Promise<vscode.ChatResult> {
    const skill = this.skillLoader.getSkill('prior-auth-azure');

    if (skill) {
      response.markdown(`Using **${skill.name}** skill for prior authorization guidance.\n\n`);
    }

    const models = await vscode.lm.selectChatModels({ family: 'gpt-4o' });

    if (models.length === 0) {
      response.markdown('No language model available.');
      return { metadata: { command: 'pa', error: 'no_model' } };
    }

    const model = models[0];

    const messages: vscode.LanguageModelChatMessage[] = [
      vscode.LanguageModelChatMessage.User(
        `You are a healthcare prior authorization expert. ${skill?.content || ''}\n\nUser question: ${request.prompt}`
      ),
    ];

    try {
      const chatResponse = await model.sendRequest(messages, {}, token);

      for await (const fragment of chatResponse.text) {
        response.markdown(fragment);
      }
    } catch (error) {
      response.markdown(`Error: ${error}`);
    }

    return { metadata: { command: 'pa' } };
  }

  private async handleValidateCommand(
    request: vscode.ChatRequest,
    response: vscode.ChatResponseStream,
    token: vscode.CancellationToken
  ): Promise<vscode.ChatResult> {
    const editor = vscode.window.activeTextEditor;

    if (!editor) {
      response.markdown('Please open a file containing a FHIR resource to validate.');
      return { metadata: { command: 'validate', error: 'no_editor' } };
    }

    const document = editor.document;
    const content = editor.selection.isEmpty
      ? document.getText()
      : document.getText(editor.selection);

    try {
      const resource = JSON.parse(content);

      if (!resource.resourceType) {
        response.markdown('The selected content does not appear to be a valid FHIR resource (missing resourceType).');
        return { metadata: { command: 'validate', error: 'invalid_resource' } };
      }

      response.markdown(`Validating **${resource.resourceType}** resource...\n\n`);

      // Perform basic validation
      const issues: string[] = [];

      // Resource-specific validations
      switch (resource.resourceType) {
        case 'Patient':
          if (!resource.identifier || resource.identifier.length === 0) {
            issues.push('⚠️ Patient should have at least one identifier');
          }
          if (!resource.name || resource.name.length === 0) {
            issues.push('⚠️ Patient should have a name');
          }
          break;

        case 'Observation':
          if (!resource.status) {
            issues.push('❌ Observation must have a status');
          }
          if (!resource.code) {
            issues.push('❌ Observation must have a code');
          }
          if (!resource.subject) {
            issues.push('⚠️ Observation should reference a subject');
          }
          break;

        case 'Condition':
          if (!resource.clinicalStatus) {
            issues.push('⚠️ Condition should have clinicalStatus');
          }
          if (!resource.code) {
            issues.push('❌ Condition must have a code');
          }
          break;
      }

      if (issues.length === 0) {
        response.markdown('✅ No validation issues found.');
      } else {
        response.markdown('**Validation Issues:**\n\n');
        for (const issue of issues) {
          response.markdown(`- ${issue}\n`);
        }
      }

    } catch (error) {
      response.markdown(`❌ Invalid JSON: ${error}`);
    }

    return { metadata: { command: 'validate' } };
  }

  private async handleGeneralQuery(
    request: vscode.ChatRequest,
    context: vscode.ChatContext,
    response: vscode.ChatResponseStream,
    token: vscode.CancellationToken
  ): Promise<vscode.ChatResult> {
    // Find relevant skills
    const relevantSkills = this.skillLoader.findSkillsForQuery(request.prompt);

    if (relevantSkills.length > 0) {
      response.markdown(
        `Found ${relevantSkills.length} relevant skill(s): ${relevantSkills.map(s => s.name).join(', ')}\n\n`
      );
    }

    const models = await vscode.lm.selectChatModels({ family: 'gpt-4o' });

    if (models.length === 0) {
      response.markdown('No language model available. Please ensure GitHub Copilot is activated.');
      return { metadata: { command: 'general', error: 'no_model' } };
    }

    const model = models[0];

    // Build context from skills
    let skillContext = '';
    for (const skill of relevantSkills.slice(0, 2)) { // Limit to 2 skills
      skillContext += this.skillLoader.getSkillContext(skill.name) + '\n\n';
    }

    const messages: vscode.LanguageModelChatMessage[] = [
      vscode.LanguageModelChatMessage.User(
        `You are an Azure healthcare development expert. Use the following context to answer questions about healthcare development on Azure.

${skillContext}

User question: ${request.prompt}`
      ),
    ];

    try {
      const chatResponse = await model.sendRequest(messages, {}, token);

      for await (const fragment of chatResponse.text) {
        response.markdown(fragment);
      }
    } catch (error) {
      response.markdown(`Error: ${error}`);
    }

    return { metadata: { command: 'general', skillsUsed: relevantSkills.map(s => s.name) } };
  }
}
