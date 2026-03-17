import { randomUUID } from "node:crypto";
import {
export type QwenDeviceAuthorization = {
export type QwenOAuthToken = {
type TokenPending = { status: "pending"; slowDown?: boolean };
type DeviceTokenResult =
async function requestDeviceCode(params:;
async function pollDeviceToken(params:;
export async function loginQwenPortalOAuth(params:;
