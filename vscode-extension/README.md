# Azure Healthcare Copilot VS Code Extension

A GitHub Copilot chat participant extension for Azure healthcare development.

## Features

- **@healthcare** chat participant for healthcare-specific queries
- `/fhir` command for Azure API for FHIR development help
- `/dicom` command for DICOM and medical imaging guidance
- `/pa` command for prior authorization workflow assistance
- `/validate` command to validate FHIR resources

## Installation

### From VSIX (Development)

1. Build the extension:
   ```bash
   npm install
   npm run compile
   ```

2. Package the extension:
   ```bash
   npx vsce package
   ```

3. Install in VS Code:
   - Open VS Code
   - Go to Extensions view
   - Click "..." menu → "Install from VSIX..."
   - Select the generated `.vsix` file

### From Marketplace (When Published)

Search for "Azure Healthcare Copilot" in the VS Code Extensions marketplace.

## Usage

### Chat with @healthcare

In the GitHub Copilot Chat panel, use `@healthcare` to ask healthcare development questions:

```
@healthcare How do I create a Patient resource in Azure FHIR?
```

### Commands

- **@healthcare /fhir** - Get help with FHIR resources and Azure API for FHIR
  ```
  @healthcare /fhir How do I search for patients by birthdate?
  ```

- **@healthcare /dicom** - Get help with DICOM and medical imaging
  ```
  @healthcare /dicom How do I store a DICOM study using STOW-RS?
  ```

- **@healthcare /pa** - Get help with prior authorization
  ```
  @healthcare /pa What documentation is needed for knee replacement PA?
  ```

- **@healthcare /validate** - Validate the current FHIR resource
  ```
  @healthcare /validate
  ```
  (Works on the active editor or selection)

## Configuration

### Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `azureHealthcare.fhirServerUrl` | Azure FHIR server URL | `""` |
| `azureHealthcare.mcpServerUrl` | Healthcare MCP server URL | `""` |
| `azureHealthcare.enableSkills` | Enable skills context injection | `true` |

### Skills

The extension automatically loads healthcare skills from:

1. **Workspace skills**: `.github/skills/` directory in your project
2. **Built-in skills**: Bundled with the extension

Each skill provides domain-specific context for better responses.

## Development

### Project Structure

```
vscode-extension/
├── src/
│   ├── extension.ts        # Extension entry point
│   ├── chat/
│   │   └── chat-handler.ts # Chat participant implementation
│   └── skills/
│       └── skill-loader.ts # Skill loading and management
├── package.json            # Extension manifest
└── tsconfig.json           # TypeScript configuration
```

### Building

```bash
# Install dependencies
npm install

# Compile
npm run compile

# Watch mode
npm run watch

# Run tests
npm test
```

### Debugging

1. Open the extension project in VS Code
2. Press F5 to launch the Extension Development Host
3. In the new window, test the `@healthcare` participant

## Requirements

- VS Code 1.85.0 or higher
- GitHub Copilot extension
- Azure account (for MCP server integration)

## License

MIT
