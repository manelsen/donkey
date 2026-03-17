import { McpServerConfig, McpServerFormData, McpRegistryEntry, McpMarketplaceCategoryInfo, McpCategory, McpMarketplaceServer } from '../types/mcp';

/**
 * Convert remote marketplace server data to McpRegistryEntry format.
 */
function convertMarketplaceToRegistry(

class McpService {

  async init(): Promise<void> {
  }

  async loadServers(): Promise<McpServerConfig[]> {
  }

  async createServer(data: McpServerFormData): Promise<{ success: boolean; servers?: McpServerConfig[]; error?: string }> {
  }

  async updateServer(id: string, data: Partial<McpServerFormData>): Promise<{ success: boolean; servers?: McpServerConfig[]; error?: string }> {
  }

  async deleteServer(id: string): Promise<{ success: boolean; servers?: McpServerConfig[]; error?: string }> {
  }

  async setServerEnabled(id: string, enabled: boolean): Promise<McpServerConfig[]> {
  }

  getServers(): McpServerConfig[] {
  }

  getEnabledServers(): McpServerConfig[] {
  }

  getServerById(id: string): McpServerConfig | undefined {
  }

  async fetchMarketplace(): Promise<{
  }

export const mcpService = new McpService();
