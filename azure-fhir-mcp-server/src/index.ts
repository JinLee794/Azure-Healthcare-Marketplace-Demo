#!/usr/bin/env node

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { AzureFhirClient } from './fhir-client.js';
import { CoveragePolicyService } from './coverage-policy.js';

// Initialize MCP server
const server = new McpServer({
  name: 'azure-fhir',
  version: '1.0.0',
});

// Initialize clients
const fhirClient = new AzureFhirClient();
const coverageService = new CoveragePolicyService();

// Tool: Search for patients
server.tool(
  'search_patients',
  'Search for patients in Azure FHIR by name, identifier, or demographics',
  {
    name: z.string().optional().describe('Patient name (partial match)'),
    identifier: z.string().optional().describe('Patient identifier (MRN, SSN, etc)'),
    birthdate: z.string().optional().describe('Patient birth date (YYYY-MM-DD)'),
    gender: z.enum(['male', 'female', 'other', 'unknown']).optional().describe('Patient gender'),
  },
  async (params) => {
    try {
      const results = await fhirClient.searchPatients(params);
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(results, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: 'text',
            text: `Error searching patients: ${error instanceof Error ? error.message : 'Unknown error'}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// Tool: Get patient by ID
server.tool(
  'get_patient',
  'Retrieve a specific patient by their FHIR resource ID',
  {
    patientId: z.string().describe('The FHIR Patient resource ID'),
  },
  async ({ patientId }) => {
    try {
      const patient = await fhirClient.getPatient(patientId);
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(patient, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: 'text',
            text: `Error retrieving patient: ${error instanceof Error ? error.message : 'Unknown error'}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// Tool: Search observations
server.tool(
  'search_observations',
  'Search for clinical observations (lab results, vital signs) for a patient',
  {
    patientId: z.string().describe('The FHIR Patient resource ID'),
    category: z.enum(['vital-signs', 'laboratory', 'social-history', 'imaging']).optional()
      .describe('Observation category'),
    code: z.string().optional().describe('LOINC code for the observation'),
    dateFrom: z.string().optional().describe('Start date for observation search (YYYY-MM-DD)'),
    dateTo: z.string().optional().describe('End date for observation search (YYYY-MM-DD)'),
  },
  async (params) => {
    try {
      const results = await fhirClient.searchObservations(params);
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(results, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: 'text',
            text: `Error searching observations: ${error instanceof Error ? error.message : 'Unknown error'}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// Tool: Check coverage policy
server.tool(
  'check_coverage_policy',
  'Check if a procedure requires prior authorization and get coverage policy details',
  {
    cptCode: z.string().describe('CPT procedure code'),
    icd10Code: z.string().optional().describe('ICD-10 diagnosis code'),
    payerId: z.string().optional().describe('Insurance payer identifier'),
  },
  async (params) => {
    try {
      const policy = await coverageService.checkPolicy(params);
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(policy, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: 'text',
            text: `Error checking coverage policy: ${error instanceof Error ? error.message : 'Unknown error'}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// Tool: Get patient coverage
server.tool(
  'get_patient_coverage',
  'Retrieve insurance coverage information for a patient',
  {
    patientId: z.string().describe('The FHIR Patient resource ID'),
  },
  async ({ patientId }) => {
    try {
      const coverage = await fhirClient.getPatientCoverage(patientId);
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(coverage, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: 'text',
            text: `Error retrieving coverage: ${error instanceof Error ? error.message : 'Unknown error'}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// Tool: Validate FHIR resource
server.tool(
  'validate_fhir_resource',
  'Validate a FHIR resource against Azure FHIR server profiles',
  {
    resourceType: z.string().describe('The FHIR resource type (Patient, Observation, etc)'),
    resource: z.string().describe('The FHIR resource JSON to validate'),
    profile: z.string().optional().describe('Optional profile URL to validate against'),
  },
  async ({ resourceType, resource, profile }) => {
    try {
      const resourceObj = JSON.parse(resource);
      const result = await fhirClient.validateResource(resourceType, resourceObj, profile);
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(result, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: 'text',
            text: `Error validating resource: ${error instanceof Error ? error.message : 'Unknown error'}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// Resources: List available resources
server.resource(
  'fhir-capability-statement',
  'Azure FHIR server capability statement',
  async () => {
    try {
      const capabilities = await fhirClient.getCapabilityStatement();
      return {
        contents: [
          {
            uri: 'fhir://capability-statement',
            mimeType: 'application/json',
            text: JSON.stringify(capabilities, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        contents: [
          {
            uri: 'fhir://capability-statement',
            mimeType: 'text/plain',
            text: `Error: ${error instanceof Error ? error.message : 'Unknown error'}`,
          },
        ],
      };
    }
  }
);

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('Azure FHIR MCP server started');
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
