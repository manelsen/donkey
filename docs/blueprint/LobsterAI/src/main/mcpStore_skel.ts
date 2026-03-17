import crypto from 'crypto';
import { Database } from 'sql.js';

export interface McpServerRecord {

export interface McpServerFormData {

interface McpServerRow {

interface McpConfigJson {

export class McpStore {


  private deserializeRow(values: unknown[]): McpServerRecord {
  }

  private serializeConfig(data: Partial<McpServerFormData>): string {
  }

  listServers(): McpServerRecord[] {
  }

  getServer(id: string): McpServerRecord | null {
  }

  createServer(data: McpServerFormData): McpServerRecord {
  }

  updateServer(id: string, data: Partial<McpServerFormData>): McpServerRecord | null {
  }

  deleteServer(id: string): boolean {
  }

  setEnabled(id: string, enabled: boolean): boolean {
  }

  getEnabledServers(): McpServerRecord[] {
  }
