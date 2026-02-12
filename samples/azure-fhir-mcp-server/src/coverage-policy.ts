interface PolicyCheckParams {
  cptCode: string;
  icd10Code?: string;
  payerId?: string;
}

interface CoveragePolicy {
  procedureCode: string;
  procedureDescription: string;
  paRequired: boolean;
  criteria?: PolicyCriteria[];
  turnaroundTime?: {
    urgent: string;
    standard: string;
  };
  validityPeriod?: string;
  documentation?: string[];
  notes?: string;
}

interface PolicyCriteria {
  type: string;
  description: string;
  required: boolean;
  codes?: string[];
  minDuration?: string;
  modality?: string;
}

// Common procedures and their PA requirements
// In production, this would be backed by Cosmos DB or similar
const POLICY_DATABASE: Map<string, CoveragePolicy> = new Map([
  ['27447', {
    procedureCode: '27447',
    procedureDescription: 'Total knee arthroplasty',
    paRequired: true,
    criteria: [
      {
        type: 'diagnosis',
        description: 'Must have documented osteoarthritis or joint damage',
        required: true,
        codes: ['M17.0', 'M17.1', 'M17.10', 'M17.11', 'M17.12'],
      },
      {
        type: 'conservative_treatment',
        description: 'Must have tried conservative treatment for at least 3 months',
        required: true,
        minDuration: '3 months',
      },
      {
        type: 'imaging',
        description: 'X-ray showing joint deterioration required',
        required: true,
        modality: 'X-ray',
      },
    ],
    turnaroundTime: {
      urgent: '24 hours',
      standard: '5 business days',
    },
    validityPeriod: '30 days',
    documentation: [
      'History and physical examination',
      'Conservative treatment records',
      'X-ray reports',
      'Functional assessment scores',
    ],
  }],
  ['70553', {
    procedureCode: '70553',
    procedureDescription: 'MRI brain with and without contrast',
    paRequired: true,
    criteria: [
      {
        type: 'clinical_indication',
        description: 'Must have documented clinical indication',
        required: true,
      },
      {
        type: 'prior_imaging',
        description: 'CT or previous MRI results if available',
        required: false,
      },
    ],
    turnaroundTime: {
      urgent: '4 hours',
      standard: '3 business days',
    },
    validityPeriod: '60 days',
    documentation: [
      'Clinical notes documenting indication',
      'Previous imaging results if applicable',
    ],
  }],
  ['99213', {
    procedureCode: '99213',
    procedureDescription: 'Office visit, established patient, low complexity',
    paRequired: false,
    notes: 'Standard office visit - no prior authorization required',
  }],
  ['99214', {
    procedureCode: '99214',
    procedureDescription: 'Office visit, established patient, moderate complexity',
    paRequired: false,
    notes: 'Standard office visit - no prior authorization required',
  }],
  ['43239', {
    procedureCode: '43239',
    procedureDescription: 'Upper GI endoscopy with biopsy',
    paRequired: true,
    criteria: [
      {
        type: 'clinical_indication',
        description: 'Must have documented symptoms or clinical indication',
        required: true,
      },
    ],
    turnaroundTime: {
      urgent: '24 hours',
      standard: '5 business days',
    },
    validityPeriod: '45 days',
    documentation: [
      'Clinical notes with symptoms',
      'Prior treatment history',
    ],
  }],
]);

export class CoveragePolicyService {
  /**
   * Check if a procedure requires prior authorization
   */
  async checkPolicy(params: PolicyCheckParams): Promise<CoveragePolicy & { found: boolean }> {
    // Look up policy by CPT code
    const policy = POLICY_DATABASE.get(params.cptCode);

    if (!policy) {
      return {
        found: false,
        procedureCode: params.cptCode,
        procedureDescription: 'Unknown procedure',
        paRequired: false,
        notes: 'Policy not found in database. Please verify with payer directly.',
      };
    }

    // In production, would also check:
    // - Payer-specific rules if payerId provided
    // - Diagnosis-specific rules if icd10Code provided
    // - Member-specific rules based on plan type

    return {
      ...policy,
      found: true,
    };
  }

  /**
   * Get all policies for a payer
   */
  async getPoliciesForPayer(payerId: string): Promise<CoveragePolicy[]> {
    // In production, would filter by payer
    return Array.from(POLICY_DATABASE.values());
  }

  /**
   * Check if diagnosis supports the procedure
   */
  async validateDiagnosisForProcedure(
    cptCode: string,
    icd10Code: string
  ): Promise<{ valid: boolean; message: string }> {
    const policy = POLICY_DATABASE.get(cptCode);

    if (!policy) {
      return {
        valid: false,
        message: 'Procedure not found in policy database',
      };
    }

    const diagnosisCriteria = policy.criteria?.find((c) => c.type === 'diagnosis');

    if (!diagnosisCriteria || !diagnosisCriteria.codes) {
      return {
        valid: true,
        message: 'No diagnosis criteria specified for this procedure',
      };
    }

    const isValid = diagnosisCriteria.codes.some(
      (code) => icd10Code.startsWith(code) || code === icd10Code
    );

    return {
      valid: isValid,
      message: isValid
        ? 'Diagnosis code is valid for this procedure'
        : `Diagnosis code ${icd10Code} is not in the approved list for procedure ${cptCode}`,
    };
  }
}
