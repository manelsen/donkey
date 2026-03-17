import { randomBytes, randomUUID } from "node:crypto";
import {
export type MiniMaxRegion = "cn" | "global";
function getOAuthEndpoints(region: MiniMaxRegion);
export type MiniMaxOAuthAuthorization = {
export type MiniMaxOAuthToken = {
type TokenPending = { status: "pending"; message?: string };
type TokenResult =
function generatePkce():;
async function requestOAuthCode(params:;
async function pollOAuthToken(params:;
export async function loginMiniMaxPortalOAuth(params:;
