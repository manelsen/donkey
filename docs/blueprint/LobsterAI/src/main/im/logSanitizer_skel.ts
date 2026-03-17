

const URL_PARAM_PATTERN = /([?&](?:access_token|accesstoken|appsecret|app_secret|clientsecret|client_secret|token)=)([^&#\s]+)/gi;
const KV_PATTERN = /((?:access[_-]?token|app[_-]?secret|app[_-]?key|client[_-]?secret|client[_-]?id|bot[_-]?token|token)\s*[:=]\s*['"]?)([^'",\s}]+)/gi;

function normalizeKey(key: string): string {
}

function isSensitiveKey(key: string): boolean {
}

export function maskSecretMiddle(value: string, keepStart = 3, keepEnd = 2): string {
  if (input.length <= keepStart + keepEnd) {
  }

export function sanitizeSensitiveString(value: string): string {

function redactSensitiveValue(value: unknown): unknown {
}

function sanitizeObject(value: unknown, seen: WeakSet<object>): unknown {
}

export function sanitizeLogArg<T>(arg: T): T {

export function sanitizeLogArgs(args: unknown[]): unknown[] {
