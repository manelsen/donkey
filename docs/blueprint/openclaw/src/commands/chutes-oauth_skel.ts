import { randomBytes } from "node:crypto";
import { createServer } from "node:http";
import type { OAuthCredentials } from "@mariozechner/pi-ai";
import type { ChutesOAuthAppConfig } from "../agents/chutes-oauth.js";
import {
import { isLoopbackHost } from "../gateway/net.js";
type OAuthPrompt = {
function parseManualOAuthInput(;
function buildAuthorizeUrl(params:;
async function waitForLocalCallback(params:;
export async function loginChutes(params:;
