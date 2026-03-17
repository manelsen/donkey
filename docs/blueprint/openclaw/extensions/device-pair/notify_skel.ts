import { promises as fs } from "node:fs";
import path from "node:path";
import type { OpenClawPluginApi } from "openclaw/plugin-sdk/device-pair";
import { listDevicePairing } from "openclaw/plugin-sdk/device-pair";
type NotifySubscription = {
type NotifyStateFile = {
export type PendingPairingRequest = {
export function formatPendingRequests(pending: PendingPairingRequest[]): string;
function resolveNotifyStatePath(stateDir: string): string;
function normalizeNotifyState(raw: unknown): NotifyStateFile;
async function readNotifyState(filePath: string): Promise<NotifyStateFile>;
async function writeNotifyState(filePath: string, state: NotifyStateFile): Promise<void>;
function notifySubscriberKey(subscriber:;
type NotifyTarget = {
function resolveNotifyTarget(ctx:;
function upsertNotifySubscriber(;
function buildPairingRequestNotificationText(request: PendingPairingRequest): string;
function requestTimestampMs(request: PendingPairingRequest): number | null;
function shouldNotifySubscriberForRequest(;
async function notifySubscriber(params:;
async function notifyPendingPairingRequests(params:;
export async function armPairNotifyOnce(params:;
export async function handleNotifyCommand(params:;
export function registerPairingNotifierService(api: OpenClawPluginApi): void;
