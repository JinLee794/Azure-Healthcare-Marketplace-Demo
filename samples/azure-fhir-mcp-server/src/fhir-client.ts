import { DefaultAzureCredential } from '@azure/identity';

interface FhirSearchParams {
  name?: string;
  identifier?: string;
  birthdate?: string;
  gender?: string;
}

interface ObservationSearchParams {
  patientId: string;
  category?: string;
  code?: string;
  dateFrom?: string;
  dateTo?: string;
}

interface FhirBundle {
  resourceType: 'Bundle';
  type: string;
  total?: number;
  entry?: Array<{ resource: unknown }>;
}

export class AzureFhirClient {
  private credential: DefaultAzureCredential;
  private baseUrl: string;
  private tokenCache: { token: string; expiresOn: number } | null = null;

  constructor() {
    this.credential = new DefaultAzureCredential();
    this.baseUrl = process.env.FHIR_SERVER_URL || '';
    
    if (!this.baseUrl) {
      console.error('Warning: FHIR_SERVER_URL environment variable not set');
    }
  }

  private async getAccessToken(): Promise<string> {
    // Check cache
    if (this.tokenCache && Date.now() < this.tokenCache.expiresOn - 60000) {
      return this.tokenCache.token;
    }

    const scope = `${this.baseUrl}/.default`;
    const tokenResponse = await this.credential.getToken(scope);
    
    if (!tokenResponse) {
      throw new Error('Failed to acquire access token');
    }

    this.tokenCache = {
      token: tokenResponse.token,
      expiresOn: tokenResponse.expiresOnTimestamp,
    };

    return tokenResponse.token;
  }

  private async fhirRequest<T>(
    method: string,
    path: string,
    body?: unknown
  ): Promise<T> {
    const token = await this.getAccessToken();
    
    const response = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/fhir+json',
        Accept: 'application/fhir+json',
      },
      body: body ? JSON.stringify(body) : undefined,
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`FHIR request failed: ${response.status} - ${errorText}`);
    }

    return response.json() as Promise<T>;
  }

  async searchPatients(params: FhirSearchParams): Promise<FhirBundle> {
    const searchParams = new URLSearchParams();
    
    if (params.name) searchParams.append('name', params.name);
    if (params.identifier) searchParams.append('identifier', params.identifier);
    if (params.birthdate) searchParams.append('birthdate', params.birthdate);
    if (params.gender) searchParams.append('gender', params.gender);

    const query = searchParams.toString();
    return this.fhirRequest<FhirBundle>('GET', `/Patient${query ? `?${query}` : ''}`);
  }

  async getPatient(patientId: string): Promise<unknown> {
    return this.fhirRequest('GET', `/Patient/${patientId}`);
  }

  async searchObservations(params: ObservationSearchParams): Promise<FhirBundle> {
    const searchParams = new URLSearchParams();
    searchParams.append('patient', params.patientId);
    
    if (params.category) searchParams.append('category', params.category);
    if (params.code) searchParams.append('code', params.code);
    if (params.dateFrom) searchParams.append('date', `ge${params.dateFrom}`);
    if (params.dateTo) searchParams.append('date', `le${params.dateTo}`);

    return this.fhirRequest<FhirBundle>('GET', `/Observation?${searchParams.toString()}`);
  }

  async getPatientCoverage(patientId: string): Promise<FhirBundle> {
    return this.fhirRequest<FhirBundle>('GET', `/Coverage?beneficiary=${patientId}`);
  }

  async validateResource(
    resourceType: string,
    resource: unknown,
    profile?: string
  ): Promise<unknown> {
    const params = new URLSearchParams();
    if (profile) params.append('profile', profile);
    
    const query = params.toString();
    return this.fhirRequest(
      'POST',
      `/${resourceType}/$validate${query ? `?${query}` : ''}`,
      resource
    );
  }

  async getCapabilityStatement(): Promise<unknown> {
    return this.fhirRequest('GET', '/metadata');
  }

  async createResource(resourceType: string, resource: unknown): Promise<unknown> {
    return this.fhirRequest('POST', `/${resourceType}`, resource);
  }

  async updateResource(
    resourceType: string,
    id: string,
    resource: unknown
  ): Promise<unknown> {
    return this.fhirRequest('PUT', `/${resourceType}/${id}`, resource);
  }

  async deleteResource(resourceType: string, id: string): Promise<void> {
    await this.fhirRequest('DELETE', `/${resourceType}/${id}`);
  }
}
