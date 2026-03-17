import { app } from 'electron';
import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from 'fs';
import { join } from 'path';

export type CoworkApiType = 'anthropic' | 'openai';

export type CoworkApiConfig = {


function getConfigPath(): string {
}

export function loadCoworkApiConfig(): CoworkApiConfig | null {

    if (config.apiKey && config.baseURL && config.model) {
    }


export function saveCoworkApiConfig(config: CoworkApiConfig): void {


  if (!config.apiKey || !config.baseURL || !config.model) {
  }

const normalized: CoworkApiConfig;


export function deleteCoworkApiConfig(): void {
