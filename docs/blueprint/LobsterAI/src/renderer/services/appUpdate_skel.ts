import { getUpdateCheckUrl, getFallbackDownloadUrl } from './endpoints';

export const UPDATE_POLL_INTERVAL_MS = 12 * 60 * 60 * 1000;
export const UPDATE_HEARTBEAT_INTERVAL_MS = 30 * 60 * 1000;

type ChangeLogLang = {

type PlatformDownload = {

type UpdateApiResponse = {

export type ChangeLogEntry = { title: string; content: string[] };

export interface AppUpdateDownloadProgress {

export interface AppUpdateInfo {

const toVersionParts = (version: string): number[] => (

const compareVersions = (a: string, b: string): number => {

  for (let i = 0; i < maxLength; i += 1) {
  }


const isNewerVersion = (latestVersion: string, currentVersion: string): boolean => (

type UpdateValue = NonNullable<NonNullable<UpdateApiResponse['data']>['value']>;

const getPlatformDownloadUrl = (value: UpdateValue | undefined): string => {

  if (platform === 'darwin') {
  }

  if (platform === 'win32') {
  }


export const checkForAppUpdate = async (currentVersion: string): Promise<AppUpdateInfo | null> => {

  if (!response.ok || typeof response.data !== 'object' || response.data === null) {
  }

  if (payload.code !== 0) {
  }


  const toEntry = (log?: ChangeLogLang): ChangeLogEntry => ({

