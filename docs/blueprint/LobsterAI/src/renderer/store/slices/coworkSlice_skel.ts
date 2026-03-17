import { createSlice, PayloadAction } from '@reduxjs/toolkit';
import type {

interface CoworkState {

const initialState: CoworkState;

const markSessionRead = (state: CoworkState, sessionId: string | null) => {

const markSessionUnread = (state: CoworkState, sessionId: string) => {

    setCoworkActive(state, action: PayloadAction<boolean>) {
    },

    setSessions(state, action: PayloadAction<CoworkSessionSummary[]>) {
    },

    setCurrentSessionId(state, action: PayloadAction<string | null>) {
    },

    setCurrentSession(state, action: PayloadAction<CoworkSession | null>) {
    },

    setDraftPrompt(state, action: PayloadAction<string>) {
    },

    addSession(state, action: PayloadAction<CoworkSession>) {
    },

    updateSessionStatus(state, action: PayloadAction<{ sessionId: string; status: CoworkSessionStatus }>) {
    },

    deleteSession(state, action: PayloadAction<string>) {
    },

    deleteSessions(state, action: PayloadAction<string[]>) {
    },

    addMessage(state, action: PayloadAction<{ sessionId: string; message: CoworkMessage }>) {
    },

    updateMessageContent(state, action: PayloadAction<{ sessionId: string; messageId: string; content: string }>) {
    },

    setStreaming(state, action: PayloadAction<boolean>) {
    },

    updateSessionPinned(state, action: PayloadAction<{ sessionId: string; pinned: boolean }>) {
    },

    updateSessionTitle(state, action: PayloadAction<{ sessionId: string; title: string }>) {
    },

    enqueuePendingPermission(state, action: PayloadAction<CoworkPermissionRequest>) {
    },

    dequeuePendingPermission(state, action: PayloadAction<{ requestId?: string } | undefined>) {
    },

    clearPendingPermissions(state) {
    },

    setConfig(state, action: PayloadAction<CoworkConfig>) {
    },

    updateConfig(state, action: PayloadAction<Partial<CoworkConfig>>) {
    },

    clearCurrentSession(state) {
    },

export const {

export default coworkSlice.reducer;
