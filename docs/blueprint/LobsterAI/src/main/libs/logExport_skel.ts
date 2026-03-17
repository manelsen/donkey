import fs from 'fs';
import { pipeline } from 'stream/promises';
import yazl from 'yazl';

export type LogArchiveEntry = {

export type ExportLogsZipInput = {

export type ExportLogsZipResult = {

export async function exportLogsZip(input: ExportLogsZipInput): Promise<ExportLogsZipResult> {
const missingEntries: string[];

  for (const entry of input.entries) {
  }


