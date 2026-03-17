/**
 * IM Chat Handler
 * Processes IM messages through LLM service with optional skills integration
 */

import axios from 'axios';
import {
import { buildIMMediaInstruction } from './imMediaInstruction';

// LLM Configuration interface (mirrors app_config structure)
interface LLMConfig {

export interface IMChatHandlerOptions {

export class IMChatHandler {

  constructor(options: IMChatHandlerOptions) {
  }

  /**
   * Process an incoming IM message and generate a response
   */
  async processMessage(message: IMMessage): Promise<string> {
  }

  /**
   * Call LLM API and get response (non-streaming for simplicity)
   */

    if (provider === 'anthropic') {
    }

    // Default to OpenAI-compatible API

  /**
   * Detect provider from config
   */
  private detectProvider(config: LLMConfig): 'anthropic' | 'openai' {
  }

  private buildOpenAICompatibleChatCompletionsUrl(config: LLMConfig): string {
  }

  private buildOpenAIResponsesUrl(config: LLMConfig): string {
  }

  private shouldUseOpenAIResponsesApi(config: LLMConfig): boolean {
  }

  private shouldUseMaxCompletionTokens(config: LLMConfig): boolean {
  }

  /**
   * Call Anthropic API
   */

const body: any;

    if (systemPrompt) {
    }


    // Extract text from response


  /**
   * Call OpenAI-compatible API
   */

const messages: Array<{ role: string; content: string }>;

    if (systemPrompt) {
    }

const body: Record<string, unknown>;
    if (useResponsesApi && systemPrompt) {
    }
    if (!useResponsesApi) {
    }

const headers: Record<string, string>;

    if (config.apiKey) {
    }


    if (useResponsesApi) {
    }

  private extractResponsesText(payload: any): string {
  }

  /**
   * Process message with streaming (for AI cards)
   */
    if (!llmConfig) {
    }

    // Build system prompt

    if (this.options.imSettings.skillsEnabled && this.options.getSkillsPrompt) {
    }

    // For now, use non-streaming and yield once
    // TODO: Implement actual streaming for better UX
