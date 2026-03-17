import { CONFIG_KEYS } from '../config';
import { localStore } from './store';


let cachedKey: CryptoKey | null;
let cachedKeyPromise: Promise<CryptoKey> | null;

export interface EncryptedPayload {

const bytesToBase64 = (bytes: Uint8Array): string => {

const base64ToBytes = (value: string): Uint8Array<ArrayBuffer> => {
  for (let i = 0; i < binary.length; i += 1) {
  }

const getLocalStorage = (): Storage | null => {
    if (typeof globalThis !== 'undefined' && 'localStorage' in globalThis) {
    }

const readRawExportKey = (stored: unknown): Uint8Array<ArrayBuffer> | null => {
  if (!stored) {
  }
  if (typeof stored === 'string') {
  }
  if (stored instanceof Uint8Array) {
  }
  if (stored instanceof ArrayBuffer) {
  }
    const data = (stored as { data: unknown[] }).data;

const readExportKeyFromLocalStorage = (): Uint8Array<ArrayBuffer> | null => {
  if (!storage) {
  }
  if (!stored) {
  }

const writeExportKeyToLocalStorage = (raw: Uint8Array) => {
  if (!storage) {
  }

const getStoredExportKey = async (): Promise<Uint8Array<ArrayBuffer> | null> => {
  if (parsed) {
  }

const persistExportKey = async (raw: Uint8Array): Promise<void> => {

const getOrCreateRawExportKey = async (): Promise<Uint8Array<ArrayBuffer>> => {
  if (stored) {
  }

const getExportKey = async (): Promise<CryptoKey> => {
  if (cachedKey) {
  }
  if (!cachedKeyPromise) {
  }

export const encryptSecret = async (value: string): Promise<EncryptedPayload> => {

export const decryptSecret = async (payload: EncryptedPayload): Promise<string> => {
  if (!payload?.encrypted || !payload?.iv) {
  }

// Password-based encryption/decryption for portable export/import

export interface PasswordEncryptedPayload {

const deriveKeyFromPassword = async (password: string, salt: Uint8Array<ArrayBuffer>): Promise<CryptoKey> => {
  if (!crypto?.subtle) {
  }

export const encryptWithPassword = async (value: string, password: string): Promise<PasswordEncryptedPayload> => {

export const decryptWithPassword = async (payload: PasswordEncryptedPayload, password: string): Promise<string> => {
  if (!payload?.encrypted || !payload?.iv || !payload?.salt) {
  }
